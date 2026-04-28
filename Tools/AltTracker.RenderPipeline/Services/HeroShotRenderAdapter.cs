using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Models;
using AltTracker.RenderPipeline.Services.HeroShot;

namespace AltTracker.RenderPipeline.Services;

public sealed class HeroShotRenderAdapter : IRenderAdapter
{
    public RenderAdapterResult Execute(
        IReadOnlyList<RenderJob> jobs,
        AppConfig config,
        CliOptions options,
        RunLogger logger)
    {
        var cfg = config.HeroShot;
        var stateStore = new HeroShotStateStore(config.TempPath);
        var validator = new HeroShotQualityValidator();

        IHeroShotRenderProvider provider;
        try
        {
            provider = CreateProvider(cfg, logger);
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
                ProcessJob(job, cfg, config, options, provider, stateStore, validator, sources, errors, logger);
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
        IHeroShotRenderProvider provider,
        HeroShotStateStore stateStore,
        HeroShotQualityValidator validator,
        Dictionary<string, string> sources,
        Dictionary<string, string> errors,
        RunLogger logger)
    {
        var c = job.Character;
        var signature = HeroShotSignatureBuilder.Compute(c, cfg);
        var stagingPath = Path.Combine(config.RenderStagingPath, job.OutputBaseName + ".png");

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

        // Resolve reference image before building the prompt so the prompt can signal its presence
        byte[]? refBytes = null;
        var refPath = ResolveReferenceImagePath(job.ManifestKey, job.OutputBaseName, cfg);
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
            logger.Info($"[HeroShot] Skipping {job.ManifestKey} — no reference image found and RequireReferenceImage=true");
            return;
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
            ReferenceImageName = refBytes is not null ? Path.GetFileName(refPath!) : "reference.png"
        };

        var response = provider.GenerateAsync(request).GetAwaiter().GetResult();

        if (!response.Success || response.ImageBytes is null)
        {
            var err = response.Error ?? "unknown error";
            logger.Error($"[HeroShot] Generation failed for {job.ManifestKey}: {err}");
            errors[job.JobKey] = err;

            if (File.Exists(stagingPath))
            {
                logger.Info($"[HeroShot] Keeping prior staging image for {job.ManifestKey}");
                sources[job.JobKey] = stagingPath;
            }
            return;
        }

        if (!string.IsNullOrWhiteSpace(response.RevisedPrompt))
        {
            logger.Info($"[HeroShot] Revised prompt: {response.RevisedPrompt[..Math.Min(120, response.RevisedPrompt.Length)]}...");
        }

        var validation = validator.Validate(response.ImageBytes);
        if (!validation.IsValid)
        {
            var err = $"quality validation failed: {validation.Reason}";
            logger.Error($"[HeroShot] {err} for {job.ManifestKey}");
            errors[job.JobKey] = err;
            if (File.Exists(stagingPath))
            {
                logger.Info($"[HeroShot] Keeping prior staging image for {job.ManifestKey}");
                sources[job.JobKey] = stagingPath;
            }
            return;
        }

        File.WriteAllBytes(stagingPath, response.ImageBytes);
        logger.Info($"[HeroShot] Staged: {stagingPath} ({response.ImageBytes.Length} bytes)");

        stateStore.Save(job.ManifestKey, new HeroShotRenderState
        {
            ManifestKey = job.ManifestKey,
            RenderSignature = signature,
            StylePreset = cfg.Style ?? "realistic",
            ProviderId = provider.ProviderId,
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

    private static string? ResolveReferenceImagePath(string manifestKey, string baseName, AppConfig.HeroShotConfig cfg)
    {
        // 1. Explicit per-character override in config
        if (cfg.CharacterReferenceImages.TryGetValue(manifestKey, out var configuredPath)
            && !string.IsNullOrWhiteSpace(configuredPath))
        {
            return configuredPath;
        }

        // 2. Convention: <realm>_<account>_<name>.png in ReferenceImagesPath
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

    private static IHeroShotRenderProvider CreateProvider(AppConfig.HeroShotConfig cfg, RunLogger logger)
    {
        var provider = (cfg.Provider ?? "openai").Trim().ToLowerInvariant();
        return provider switch
        {
            "openai"          => new OpenAiHeroShotProvider(cfg, logger),
            "browserchatgpt"  => new BrowserChatGptProvider(cfg, logger),
            "manual"          => new ManualHeroShotProvider(cfg, logger),
            _ => throw new PipelineDataException(
                     $"HeroShot: Unknown provider '{cfg.Provider}'. Supported: openai, browserchatgpt, manual")
        };
    }
}
