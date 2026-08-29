using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Models;
using AltTracker.RenderPipeline.Services.BattleNet;
using AltTracker.RenderPipeline.Services.HeroShot;

namespace AltTracker.RenderPipeline.Services;

public sealed class HeroShotRenderAdapter : IRenderAdapter
{
    private readonly ArmoryReferenceResolver? _armory;

    // Render state is staged here and only written to disk once Program has converted, copied and
    // recorded the image. Saving it at generation time would mark a render "done" that never
    // actually got published: a later conversion/copy/manifest failure would leave the stored
    // reference fingerprint matching the live one, so --refresh-armory would see no difference and
    // the unchanged gear hash would give the planner no other reason to retry - silently dropping
    // the update instead of re-running it.
    private readonly Dictionary<string, (string ManifestKey, HeroShotRenderState State)> _pendingStates =
        new(StringComparer.OrdinalIgnoreCase);
    private HeroShotStateStore? _stateStore;

    /// <summary>
    /// Persists the render state for a job whose image was successfully published. No-op for jobs
    /// that were skipped or that failed.
    /// </summary>
    public void CommitPendingState(string jobKey)
    {
        if (_stateStore is null) return;
        if (!_pendingStates.Remove(jobKey, out var pending)) return;
        _stateStore.Save(pending.ManifestKey, pending.State);
    }

    /// <param name="armory">
    /// Supplies Battle.net armory renders as the highest-priority reference source. Shared with the
    /// --refresh-armory preflight so each character is fetched at most once per run. Null disables
    /// the tier entirely and the existing screenshot tiers are used unchanged.
    /// </param>
    public HeroShotRenderAdapter(ArmoryReferenceResolver? armory = null)
    {
        _armory = armory;
    }

    public RenderAdapterResult Execute(
        IReadOnlyList<RenderJob> jobs,
        AppConfig config,
        CliOptions options,
        RunLogger logger)
    {
        var cfg = config.HeroShot;
        var stateStore = new HeroShotStateStore(config.TempPath);
        _stateStore = stateStore;
        _pendingStates.Clear();
        var validator = new HeroShotQualityValidator();

        // Providers are cached by name: the default plus any per-character overrides. All names are
        // resolved up front so a typo fails the run immediately rather than mid-way through.
        var providerCache = new Dictionary<string, IHeroShotRenderProvider>(StringComparer.OrdinalIgnoreCase);
        IHeroShotRenderProvider provider;
        try
        {
            provider = GetProvider(cfg.Provider, cfg, providerCache, logger);
            foreach (var overrideName in cfg.CharacterProviders.Values)
            {
                GetProvider(overrideName, cfg, providerCache, logger);
            }
        }
        catch (PipelineDataException ex)
        {
            logger.Error(ex.Message);
            var allErrors = jobs.ToDictionary(j => j.JobKey, _ => ex.Message, StringComparer.OrdinalIgnoreCase);
            return new RenderAdapterResult(
                new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase),
                allErrors);
        }

        logger.Info($"[HeroShot] Provider: {provider.ProviderId}, Model: {cfg.Model}, Style: {cfg.Style}");
        if (cfg.CharacterProviders.Count > 0)
        {
            logger.Info($"[HeroShot] Per-character provider overrides: "
                      + string.Join(", ", cfg.CharacterProviders.Select(kv => $"{kv.Key}={kv.Value}")));
        }
        logger.Info($"[HeroShot] Prompt template: {cfg.PromptTemplateVersion}, Gen version: {cfg.GenerationVersion}");

        var sources = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var errors = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        Directory.CreateDirectory(config.RenderStagingPath);

        foreach (var job in jobs)
        {
            if (options.DryRun)
            {
                logger.Info($"[HeroShot][dry-run] Would generate hero shot for {job.ManifestKey}");
                continue;
            }

            try
            {
                ProcessJob(job, cfg, config, options, providerCache, stateStore, validator, _armory,
                           sources, errors, _pendingStates, logger);
            }
            catch (Exception ex)
            {
                logger.Error($"[HeroShot] Unhandled error for {job.ManifestKey}: {ex.Message}");
                errors[job.JobKey] = ex.Message;
            }
        }

        return new RenderAdapterResult(sources, errors);
    }

    private static void ProcessJob(
        RenderJob job,
        AppConfig.HeroShotConfig cfg,
        AppConfig config,
        CliOptions options,
        Dictionary<string, IHeroShotRenderProvider> providerCache,
        HeroShotStateStore stateStore,
        HeroShotQualityValidator validator,
        ArmoryReferenceResolver? armory,
        Dictionary<string, string> sources,
        Dictionary<string, string> errors,
        Dictionary<string, (string ManifestKey, HeroShotRenderState State)> pendingStates,
        RunLogger logger)
    {
        var c = job.Character;
        var stagingPath = Path.Combine(config.RenderStagingPath, job.OutputBaseName + ".png");

        // The reference MUST be resolved before the signature is computed: the signature now
        // includes the reference fingerprint, so an armory render that changed since the last run
        // has to be in hand before the skip decision is made. Computing the signature first (as this
        // did previously) meant a refreshed reference could never invalidate the cache.
        byte[]? refBytes = null;
        var refPath = ResolveReferenceImagePath(c, job.ManifestKey, job.OutputBaseName, cfg, armory, logger);
        var refFingerprint = "";
        if (!string.IsNullOrWhiteSpace(refPath) && File.Exists(refPath))
        {
            refBytes = File.ReadAllBytes(refPath);
            refFingerprint = HeroShotSignatureBuilder.ComputeFileFingerprint(refPath);
            logger.Info($"[HeroShot] Reference image: {refPath} ({refBytes.Length} bytes)");
        }
        else if (!string.IsNullOrWhiteSpace(refPath))
        {
            logger.Warn($"[HeroShot] Reference image not found at configured path: {refPath}");
        }

        if (cfg.RequireReferenceImage && refBytes is null)
        {
            var skipReason = "no reference image found and RequireReferenceImage=true";
            logger.Info($"[HeroShot] Skipping {job.ManifestKey} — {skipReason}");
            errors[job.JobKey] = skipReason;
            return;
        }

        // A per-character override beats the global default, so one character can prefer the raw
        // armory render while the rest prefer AI generation.
        var preferredProvider = cfg.CharacterProviders.TryGetValue(job.ManifestKey, out var perCharacter)
                                && !string.IsNullOrWhiteSpace(perCharacter)
            ? perCharacter
            : cfg.Provider;

        // Ordered fallback chain. Whichever source is preferred, the other is tried before giving
        // up; if every source fails the job produces no image, and the addon draws its identity
        // card instead. "manual" is an explicit import path, so it never chains.
        var chain = BuildProviderChain(preferredProvider);

        byte[]? armoryBytes = null;
        if (chain.Contains("armory", StringComparer.OrdinalIgnoreCase) && armory is { Available: true })
        {
            var armoryReference = armory.TryResolve(c, job.ManifestKey, job.OutputBaseName);
            if (armoryReference is not null && File.Exists(armoryReference.RawPath))
            {
                armoryBytes = File.ReadAllBytes(armoryReference.RawPath);
            }
        }

        // The signature tracks what was ASKED for, not which link of the chain answered - otherwise
        // a run that fell back would look like a configuration change on the next run and re-render.
        var signature = HeroShotSignatureBuilder.Compute(c, cfg, refFingerprint, preferredProvider);

        if (!options.ForceAll)
        {
            var priorState = stateStore.TryLoad(job.ManifestKey);
            if (priorState is not null
                && priorState.RenderSignature == signature
                && File.Exists(stagingPath)
                && File.Exists(job.FinalOutputPath))
            {
                logger.Info($"[HeroShot] Signature unchanged, skipping generation for {job.ManifestKey}");
                sources[job.JobKey] = stagingPath;
                return;
            }
        }

        var prompt = HeroShotPromptBuilder.Build(c, cfg.Style ?? "realistic", hasReferenceImage: refBytes is not null);
        logger.Info($"[HeroShot] Prompt for {job.ManifestKey}: {prompt[..Math.Min(120, prompt.Length)]}...");

        var request = new HeroShotRequest
        {
            IdempotencyKey = $"{job.ManifestKey}|{signature}",
            Prompt = prompt,
            StylePreset = cfg.Style ?? "realistic",
            Width = cfg.Width,
            Height = cfg.Height,
            ReferenceImageBytes = refBytes,
            ReferenceImageName = refBytes is not null ? Path.GetFileName(refPath!) : "reference.png",
            ArmoryRenderBytes = armoryBytes
        };

        // Walk the chain: first provider that returns a valid image wins.
        byte[]? imageBytes = null;
        string? usedProvider = null;
        var attemptErrors = new List<string>();

        foreach (var candidate in chain)
        {
            var provider = GetProvider(candidate, cfg, providerCache, logger);
            if (chain.Count > 1)
            {
                logger.Info($"[HeroShot] Trying provider '{provider.ProviderId}' for {job.ManifestKey}.");
            }

            var response = provider.GenerateAsync(request).GetAwaiter().GetResult();

            if (!response.Success || response.ImageBytes is null)
            {
                var err = $"{provider.ProviderId}: {response.Error ?? "unknown error"}";
                logger.Error($"[HeroShot] Generation failed for {job.ManifestKey} - {err}");
                attemptErrors.Add(err);
                continue;
            }

            if (!string.IsNullOrWhiteSpace(response.RevisedPrompt))
            {
                logger.Info($"[HeroShot] Revised prompt: {response.RevisedPrompt[..Math.Min(120, response.RevisedPrompt.Length)]}...");
            }

            var validation = validator.Validate(response.ImageBytes);
            if (!validation.IsValid)
            {
                var err = $"{provider.ProviderId}: quality validation failed: {validation.Reason}";
                logger.Error($"[HeroShot] {err} for {job.ManifestKey}");
                attemptErrors.Add(err);
                continue;
            }

            imageBytes = response.ImageBytes;
            usedProvider = provider.ProviderId;
            break;
        }

        if (imageBytes is null || usedProvider is null)
        {
            errors[job.JobKey] = string.Join(" | ", attemptErrors);

            // Retain the previous image so the portrait does not blank out. Program treats a
            // retained source as a failure and leaves the manifest untouched, so the next run
            // retries rather than publishing this as current.
            if (File.Exists(stagingPath))
            {
                logger.Info($"[HeroShot] Keeping prior staging image for {job.ManifestKey}");
                sources[job.JobKey] = stagingPath;
            }
            return;
        }

        if (!string.Equals(usedProvider, chain[0], StringComparison.OrdinalIgnoreCase))
        {
            logger.Warn($"[HeroShot] {job.ManifestKey}: '{chain[0]}' failed; fell back to '{usedProvider}'.");
        }

        File.WriteAllBytes(stagingPath, imageBytes);
        logger.Info($"[HeroShot] Staged: {stagingPath} ({imageBytes.Length} bytes)");

        pendingStates[job.JobKey] = (job.ManifestKey, new HeroShotRenderState
        {
            ManifestKey = job.ManifestKey,
            RenderSignature = signature,
            StylePreset = cfg.Style ?? "realistic",
            ProviderId = usedProvider,
            ProviderModel = cfg.Model ?? "",
            PromptTemplateVersion = cfg.PromptTemplateVersion ?? "v1",
            GenerationVersion = cfg.GenerationVersion ?? "1",
            Width = cfg.OutputWidth,
            Height = cfg.OutputHeight,
            OutputFormat = cfg.Format ?? "tga",
            GeneratedAt = DateTimeOffset.UtcNow.ToString("O"),
            ReferenceFingerprint = refFingerprint
        });

        sources[job.JobKey] = stagingPath;
    }

    private static string? ResolveReferenceImagePath(
        CharacterRecord character, string manifestKey, string baseName, AppConfig.HeroShotConfig cfg,
        ArmoryReferenceResolver? armory, RunLogger logger)
    {
        // 0. Battle.net armory render. Blizzard regenerates it whenever the character logs out, so
        //    it is gear-accurate without anyone taking a screenshot. Skipped when an explicit
        //    per-character override is configured, so that manual escape hatch still wins.
        if (armory is { Available: true } && !cfg.CharacterReferenceImages.ContainsKey(manifestKey))
        {
            var reference = armory.TryResolve(character, manifestKey, baseName);
            if (reference is not null)
            {
                logger.Info($"[HeroShot] Using armory render for {manifestKey}: {reference.PreparedPath}");
                return reference.PreparedPath;
            }
            logger.Verbose($"[HeroShot] No armory render for {manifestKey}; falling back to local references.");
        }

        // 1. Fresh in-game capture (/alts update-reference): if the addon stamped a refshot_ts and a
        //    Screenshots/ file exists near that time, prefer it — it beats a stale saved reference.
        if (character.ReferenceShotEpoch > 0 && !string.IsNullOrWhiteSpace(cfg.ScreenshotsDirectory)
            && Directory.Exists(cfg.ScreenshotsDirectory))
        {
            var shot = FindScreenshotNearEpoch(cfg.ScreenshotsDirectory, character.ReferenceShotEpoch);
            if (shot is not null)
            {
                logger.Info($"[HeroShot] Using fresh in-game capture for {manifestKey}: {shot}");
                return shot;
            }
            logger.Warn($"[HeroShot] {manifestKey} has refshot_ts={character.ReferenceShotEpoch} but no matching screenshot in {cfg.ScreenshotsDirectory}; falling back.");
        }

        // 2. Explicit per-character override in config
        if (cfg.CharacterReferenceImages.TryGetValue(manifestKey, out var configuredPath)
            && !string.IsNullOrWhiteSpace(configuredPath))
        {
            return configuredPath;
        }

        // 3. Convention: <realm>_<account>_<name>.png in ReferenceImagesPath
        if (!string.IsNullOrWhiteSpace(cfg.ReferenceImagesPath))
        {
            var extensions = new[] { ".png", ".jpg", ".jpeg", ".tga" };
            foreach (var ext in extensions)
            {
                var conventionPath = Path.Combine(cfg.ReferenceImagesPath, baseName + ext);
                if (File.Exists(conventionPath)) return conventionPath;
            }
        }

        return null;
    }

    /// <summary>
    /// Finds the screenshot whose file time is closest to <paramref name="epoch"/> (the addon's
    /// capture marker), within a tolerance window. WoW writes the file the instant Screenshot()
    /// fires, so its mtime lines up with refshot_ts regardless of when SavedVariables was flushed.
    /// </summary>
    private static string? FindScreenshotNearEpoch(string dir, long epoch)
    {
        var target = DateTimeOffset.FromUnixTimeSeconds(epoch);
        var tolerance = TimeSpan.FromSeconds(45);
        string? best = null;
        var bestDelta = tolerance;

        foreach (var f in Directory.EnumerateFiles(dir))
        {
            var ext = Path.GetExtension(f).ToLowerInvariant();
            if (ext is not (".jpg" or ".jpeg" or ".tga" or ".png")) continue;
            var mtime = new DateTimeOffset(File.GetLastWriteTimeUtc(f), TimeSpan.Zero);
            var delta = (mtime - target).Duration();
            if (delta <= bestDelta)
            {
                bestDelta = delta;
                best = f;
            }
        }
        return best;
    }

    /// <summary>
    /// Ordered provider chain for a character: the preferred source first, the other as fallback.
    ///
    /// "manual" is an explicit hand-import path rather than a generator, so it never chains -
    /// silently substituting something else would hide the fact that the import was missing.
    /// </summary>
    internal static IReadOnlyList<string> BuildProviderChain(string? preferred)
    {
        // Null, empty and whitespace all mean "not configured" - a bare ?? would let "" through
        // and produce a chain of one unusable name.
        var name = string.IsNullOrWhiteSpace(preferred) ? "codex" : preferred.Trim().ToLowerInvariant();
        return name switch
        {
            "codex"  => ["codex", "armory"],
            "armory" => ["armory", "codex"],
            _        => [name],
        };
    }

    private static IHeroShotRenderProvider GetProvider(
        string? name,
        AppConfig.HeroShotConfig cfg,
        Dictionary<string, IHeroShotRenderProvider> cache,
        RunLogger logger)
    {
        var provider = (name ?? "codex").Trim().ToLowerInvariant();
        if (cache.TryGetValue(provider, out var existing)) return existing;

        IHeroShotRenderProvider created = provider switch
        {
            "codex"   => new CodexImagegenProvider(cfg, logger),
            "manual"  => new ManualHeroShotProvider(cfg, logger),
            "armory"  => new ArmoryHeroShotProvider(cfg, logger),
            _ => throw new PipelineDataException(
                     $"HeroShot: Unknown provider '{name}'. Supported: codex, manual, armory")
        };

        cache[provider] = created;
        return created;
    }
}
