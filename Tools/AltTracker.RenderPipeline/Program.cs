using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Models;
using AltTracker.RenderPipeline.Services;

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

    var planner = new RenderPlanner();
    var plan = planner.BuildPlan(characters, existingManifest, config, options, logger);

    logger.Info($"Render candidates selected: {plan.Jobs.Count}");
    logger.Info($"Skipped unchanged characters: {plan.SkippedCount}");
    logger.Info($"Render spec: {config.RenderSpec.Width}x{config.RenderSpec.Height}, transparentPreferred={config.RenderSpec.PreferTransparentBackground}, framing={config.RenderSpec.FramingPreset}");
    logger.Info($"WMVx policy: preferredClient={config.WmvxPolicy.PreferredClientProfile}, fallbackClient={config.WmvxPolicy.FallbackClientProfile}, allowAnyWorking={config.WmvxPolicy.AllowAnyWorkingClientProfile}, missingItemPolicy={config.WmvxPolicy.MissingItemPolicy}");

    IRenderAdapter adapter = config.RenderBackend switch
    {
        "WowConverter" => new WowConverterRenderAdapter(),
        "HeroShot" => new HeroShotRenderAdapter(),
        _ => new ManualWmvxRenderAdapter()
    };
    logger.Info($"Render backend: {config.RenderBackend}");
    var renderResult = adapter.Execute(plan.Jobs, config, options, logger);

    var converter = new ImageConverter();
    var successful = 0;
    var failed = 0;

    foreach (var job in plan.Jobs)
    {
        if (!renderResult.SourceByJobKey.TryGetValue(job.JobKey, out var sourcePath))
        {
            if (options.DryRun)
            {
                logger.Info($"[dry-run] Render would be required for {job.JobKey} but staged image is currently missing.");
            }
            else
            {
                if (renderResult.ErrorByJobKey.TryGetValue(job.JobKey, out var renderError) && !string.IsNullOrWhiteSpace(renderError))
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

        successful++;
        existingManifest[job.ManifestKey] = ManifestEntry.FromJob(job, config);
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
