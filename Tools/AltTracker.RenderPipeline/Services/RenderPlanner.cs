using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Models;

namespace AltTracker.RenderPipeline.Services;

public sealed class RenderPlanner
{
    public PlanResult BuildPlan(
        IReadOnlyList<CharacterRecord> characters,
        IReadOnlyDictionary<string, ManifestEntry> manifest,
        AppConfig config,
        CliOptions options,
        RunLogger logger)
    {
        var jobs = new List<RenderJob>();
        var skipped = 0;
        var now = DateTimeOffset.UtcNow;

        foreach (var c in characters)
        {
            var baseName = PathTools.BuildOutputBaseName(c);
            var manifestKey = PathTools.BuildManifestKey(c);
            var finalPath = Path.Combine(config.OutputRenderDirectory, baseName + ".tga");
            var finalAddonFilename = baseName + ".tga";
            var finalAddonImagePath = PathTools.CombineWowPath(config.WowAddonImageRoot, finalAddonFilename);
            var gearHash = PathTools.ComputeGearHash(c, config.RenderProfileVersion);
            var expectedStagingFile = baseName + PathTools.NormalizeExtension(config.RenderSpec.PreferredStagingExtension, ".png");

            var reasons = new List<string>();
            var filterMatch = options.CharacterFilters.Count == 0
                || options.CharacterFilters.Contains(manifestKey)
                || options.CharacterFilters.Contains(baseName)
                || options.CharacterFilters.Contains(c.Name);

            if (!filterMatch) continue;
            if (options.ForceAll) reasons.Add("force-all");
            if (!File.Exists(finalPath)) reasons.Add("missing-output-image");
            if (!manifest.TryGetValue(manifestKey, out var entry))
            {
                reasons.Add("missing-manifest-entry");
            }
            else
            {
                if (!string.Equals(entry.GearHash, gearHash, StringComparison.OrdinalIgnoreCase))
                {
                    reasons.Add("gear-hash-changed");
                }
                if (DateTimeOffset.TryParse(entry.GeneratedAt, out var generatedAt))
                {
                    if (c.LastUpdateEpoch > 0)
                    {
                        var lastUpdate = DateTimeOffset.FromUnixTimeSeconds(c.LastUpdateEpoch);
                        if (lastUpdate > generatedAt) reasons.Add("character-updated-after-render");
                    }
                    if (config.MaxAgeDays > 0 && (now - generatedAt).TotalDays > config.MaxAgeDays)
                    {
                        reasons.Add("render-age-threshold");
                    }
                }
                else
                {
                    reasons.Add("invalid-manifest-generatedAt");
                }
            }

            if (reasons.Count == 0)
            {
                skipped++;
                logger.Verbose($"Skipped unchanged: {manifestKey}");
                continue;
            }

            jobs.Add(new RenderJob
            {
                JobKey = manifestKey,
                ManifestKey = manifestKey,
                Character = c,
                OutputBaseName = baseName,
                FinalOutputPath = finalPath,
                FinalAddonImagePath = finalAddonImagePath,
                FinalAddonFilename = finalAddonFilename,
                ExpectedStagingFileName = expectedStagingFile,
                GearHash = gearHash,
                Reason = string.Join(",", reasons)
            });
        }

        if (options.MaxJobs is > 0 && jobs.Count > options.MaxJobs.Value)
        {
            jobs = jobs.Take(options.MaxJobs.Value).ToList();
        }

        return new PlanResult(jobs, skipped);
    }
}

public sealed record PlanResult(IReadOnlyList<RenderJob> Jobs, int SkippedCount);
