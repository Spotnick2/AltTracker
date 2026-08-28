using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Models;
using AltTracker.RenderPipeline.Services;
using AltTracker.RenderPipeline.Services.BattleNet;
using AltTracker.RenderPipeline.Services.HeroShot;

var options = CliOptions.Parse(args);
var logger = new RunLogger(options.Verbose);

try
{
    var config = AppConfig.Load(options, logger);
    logger.Info("Config loaded.");

    if (!File.Exists(config.InputDataPath))
    {
        logger.Error($"Input data path not found: {config.InputDataPath}");
        return (int)PipelineExitCode.ConfigurationError;
    }

    var source = new SavedVariablesCharacterSource();
    var characters = source.LoadCharacters(config.InputDataPath, logger);
    logger.Info($"Characters discovered: {characters.Count}");
    ApplyInteractiveSelection(options, characters, logger);

    var manifestStore = new ManifestLuaStore();
    var existingManifest = new Dictionary<string, ManifestEntry>(
        manifestStore.Read(config.ManifestOutputPath, logger),
        StringComparer.OrdinalIgnoreCase);

    // Battle.net armory renders are the preferred reference source. Created once and shared with
    // the render adapter so each character is fetched at most once per run.
    using var armory = ArmoryReferenceResolver.Create(config, logger);
    if (!armory.Available)
    {
        logger.Info($"[BattleNet] Armory references disabled: {armory.UnavailableReason}");
    }

    // Remote checks are opt-in. An ordinary run stays entirely offline; --refresh-armory asks
    // Battle.net whether any render changed and lets those characters become jobs.
    // A plain --dry-run stays entirely offline. Combining it with --refresh-armory is a deliberate
    // double opt-in that previews which characters would be re-rendered, without generating
    // anything: the render adapter still short-circuits on DryRun before any provider call.
    IReadOnlySet<string>? armoryUpdatedKeys = null;
    if (options.RefreshArmory && armory.Available)
    {
        logger.Info(options.DryRun
            ? "[BattleNet] Checking the armory for updated renders (read-only preview; nothing will be generated)..."
            : "[BattleNet] Checking the armory for updated character renders...");
        var preflightCharacters = characters.Where(c => RenderPlanner.MatchesFilter(c, options)).ToList();
        armoryUpdatedKeys = armory.FindChangedCharacters(preflightCharacters, new HeroShotStateStore(config.TempPath));
        logger.Info($"[BattleNet] Characters with an updated render: {armoryUpdatedKeys.Count}");
    }

    var planner = new RenderPlanner();
    var plan = planner.BuildPlan(characters, existingManifest, config, options, logger, armoryUpdatedKeys);

    logger.Info($"Render candidates selected: {plan.Jobs.Count}");
    logger.Info($"Skipped unchanged characters: {plan.SkippedCount}");
    logger.Info($"Render spec: {config.RenderSpec.Width}x{config.RenderSpec.Height}, transparentPreferred={config.RenderSpec.PreferTransparentBackground}, framing={config.RenderSpec.FramingPreset}");

    // HeroShot (codex imagegen) is the only render backend.
    var heroShotAdapter = new HeroShotRenderAdapter(armory);
    IRenderAdapter adapter = heroShotAdapter;
    logger.Info($"Render backend: {config.RenderBackend}");
    var renderResult = adapter.Execute(plan.Jobs, config, options, logger);

    var converter = new ImageConverter();
    var successful = 0;
    var failed = 0;
    // Jobs whose image reached disk. Their render state is only persisted once the manifest write
    // has also succeeded, so a failure anywhere in publishing leaves the job looking un-rendered
    // and it is retried next run instead of being silently considered done.
    var publishedJobKeys = new List<string>();

    foreach (var job in plan.Jobs)
    {
        // The adapter records an error when generation or quality validation failed. It may still
        // hand back the *previous* staging image so the portrait does not blank out (see
        // HeroShotRenderAdapter "Keeping prior staging image"). That retained image is stale, so it
        // must never be published under the new gear hash.
        renderResult.ErrorByJobKey.TryGetValue(job.JobKey, out var renderError);
        var hasRenderError = !string.IsNullOrWhiteSpace(renderError);

        if (!renderResult.SourceByJobKey.TryGetValue(job.JobKey, out var sourcePath))
        {
            if (options.DryRun)
            {
                logger.Info($"[dry-run] Render would be required for {job.JobKey} but staged image is currently missing.");
            }
            else
            {
                if (hasRenderError)
                {
                    logger.Warn($"Render missing for {job.JobKey}: {renderError}");
                }
                else
                {
                    logger.Warn($"Render missing for {job.JobKey} (expected staged image not found).");
                }
                failed++;
            }
            continue;
        }

        var conversion = converter.ConvertToTga(sourcePath, job.FinalOutputPath, config, options, logger);
        if (!conversion.Success)
        {
            logger.Error($"Conversion failed for {job.JobKey}: {conversion.Error}");
            failed++;
            continue;
        }

        if (!PathTools.IsValidWowAddonImagePath(job.FinalAddonImagePath))
        {
            logger.Error($"Invalid addon image path for manifest ({job.JobKey}): {job.FinalAddonImagePath}");
            failed++;
            continue;
        }

        if (!options.DryRun && !string.IsNullOrWhiteSpace(config.AddonMediaDirectory))
        {
            var addonTarget = Path.Combine(config.AddonMediaDirectory, Path.GetFileName(job.FinalOutputPath));
            if (!Path.GetFullPath(addonTarget).Equals(Path.GetFullPath(job.FinalOutputPath), StringComparison.OrdinalIgnoreCase))
            {
                Directory.CreateDirectory(Path.GetDirectoryName(addonTarget)!);
                File.Copy(job.FinalOutputPath, addonTarget, overwrite: true);
                logger.Info($"File written: {addonTarget}");
            }
        }

        if (hasRenderError)
        {
            // Stale image retained: refresh the .tga so the addon keeps a valid texture, but leave
            // the manifest entry untouched so the planner still sees the change and retries.
            logger.Warn($"Render failed for {job.JobKey}: {renderError}. Kept the previous image; manifest entry left unchanged so the next run retries.");
            failed++;
        }
        else
        {
            successful++;
            existingManifest[job.ManifestKey] = ManifestEntry.FromJob(job, config);
            publishedJobKeys.Add(job.JobKey);
        }
    }

    if (!options.DryRun)
    {
        var writeOk = manifestStore.Write(config.ManifestOutputPath, existingManifest, logger);
        if (!writeOk)
        {
            logger.Error("Manifest write failed.");
            return (int)PipelineExitCode.PublishError;
        }
        logger.Info($"Manifest written: {config.ManifestOutputPath}");

        // Publish succeeded end to end, so it is now safe to record these renders as done.
        foreach (var jobKey in publishedJobKeys)
        {
            heroShotAdapter.CommitPendingState(jobKey);
        }
    }
    else
    {
        logger.Info("Dry-run enabled; no files or manifest written.");
    }

    logger.Info($"Summary: jobs={plan.Jobs.Count}, rendered={successful}, failed={failed}, skipped={plan.SkippedCount}");

    if (failed > 0)
    {
        return successful > 0 ? (int)PipelineExitCode.PartialSuccess : (int)PipelineExitCode.RenderStageFailure;
    }

    return (int)PipelineExitCode.Success;
}
catch (PipelineDataException ex)
{
    logger.Error(ex.Message);
    return (int)PipelineExitCode.DataError;
}
catch (Exception ex)
{
    logger.Error($"Unhandled error: {ex.Message}");
    return (int)PipelineExitCode.ConfigurationError;
}

void ApplyInteractiveSelection(CliOptions options, IReadOnlyList<CharacterRecord> characters, RunLogger logger)
{
    if (!options.InteractiveSelection) return;
    if (Console.IsInputRedirected)
    {
        logger.Warn("--interactive requested but console input is redirected. Skipping interactive selector.");
        return;
    }

    var entries = characters
        .Select(c => new CharacterPickEntry(
            PathTools.BuildManifestKey(c),
            PathTools.BuildOutputBaseName(c),
            c.Class ?? "",
            c.Level))
        .OrderBy(e => e.ManifestKey, StringComparer.OrdinalIgnoreCase)
        .ToList();

    if (entries.Count == 0)
    {
        logger.Warn("No characters available for interactive selection.");
        return;
    }

    Console.WriteLine();
    Console.WriteLine("=== AltTracker character selection ===");
    Console.WriteLine("1) Regenerate ALL characters (force)");
    Console.WriteLine("2) Regenerate SELECTED characters (force)");
    Console.WriteLine("3) Default behavior (only stale/missing characters)");
    Console.Write("Choice [1/2/3] (default 3): ");
    var choice = (Console.ReadLine() ?? "3").Trim();
    if (string.IsNullOrWhiteSpace(choice)) choice = "3";

    if (choice == "1")
    {
        options.CharacterFilters.Clear();
        options.ForceAll = true;
        logger.Info("Interactive selector: regenerating ALL characters.");
        return;
    }

    if (choice == "2")
    {
        Console.WriteLine();
        for (var i = 0; i < entries.Count; i++)
        {
            var e = entries[i];
            Console.WriteLine($"{i + 1,2}) {e.ManifestKey} [{e.BaseName}] L{e.Level} {e.ClassName}");
        }
        Console.WriteLine();
        Console.Write("Enter numbers (comma-separated, ranges like 3-6): ");
        var rawSelection = Console.ReadLine() ?? "";
        var indices = ParseSelectionIndices(rawSelection, entries.Count);
        if (indices.Count == 0)
        {
            throw new PipelineDataException("Interactive selection received no valid character indices.");
        }

        options.CharacterFilters.Clear();
        foreach (var idx in indices)
        {
            options.CharacterFilters.Add(entries[idx - 1].ManifestKey);
        }
        options.ForceAll = true;
        logger.Info($"Interactive selector: regenerating {indices.Count} selected character(s).");
        return;
    }

    logger.Info("Interactive selector: keeping default stale/missing selection behavior.");
}

HashSet<int> ParseSelectionIndices(string raw, int max)
{
    var set = new HashSet<int>();
    if (string.IsNullOrWhiteSpace(raw)) return set;

    var tokens = raw.Split([',', ';', ' ', '\t'], StringSplitOptions.RemoveEmptyEntries);
    foreach (var tokenRaw in tokens)
    {
        var token = tokenRaw.Trim();
        if (token.Equals("all", StringComparison.OrdinalIgnoreCase))
        {
            for (var i = 1; i <= max; i++) set.Add(i);
            continue;
        }

        var dash = token.IndexOf('-', StringComparison.Ordinal);
        if (dash > 0 && dash < token.Length - 1)
        {
            var left = token[..dash];
            var right = token[(dash + 1)..];
            if (int.TryParse(left, out var start) && int.TryParse(right, out var end))
            {
                if (start > end) (start, end) = (end, start);
                start = Math.Max(1, start);
                end = Math.Min(max, end);
                for (var i = start; i <= end; i++) set.Add(i);
            }
            continue;
        }

        if (int.TryParse(token, out var single) && single >= 1 && single <= max)
        {
            set.Add(single);
        }
    }
    return set;
}

sealed record CharacterPickEntry(string ManifestKey, string BaseName, string ClassName, int Level);
