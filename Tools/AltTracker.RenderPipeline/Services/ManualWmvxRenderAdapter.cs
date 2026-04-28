using System.Text;
using System.Text.Json;
using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Models;

namespace AltTracker.RenderPipeline.Services;

public sealed class ManualWmvxRenderAdapter : IRenderAdapter
{
    private static readonly string[] SupportedStagingExtensions = [".png", ".jpg", ".jpeg", ".bmp", ".tga"];

    public RenderAdapterResult Execute(
        IReadOnlyList<RenderJob> jobs,
        AppConfig config,
        CliOptions options,
        RunLogger logger)
    {
        Directory.CreateDirectory(config.TempPath);
        Directory.CreateDirectory(config.RenderStagingPath);
        Directory.CreateDirectory(config.OutputRenderDirectory);

        if (string.IsNullOrWhiteSpace(config.WmvxExePath) || !File.Exists(config.WmvxExePath))
        {
            logger.Warn($"WMVx executable not found at configured path: {config.WmvxExePath}");
            logger.Warn("Stock WMVx automation is not verified; using manual staging workflow.");
        }
        else
        {
            logger.Info($"WMVx invocation path configured: {config.WmvxExePath}");
            logger.Info("MVP uses manual render staging (no assumed WMVx headless automation).");
        }

        var jobsJsonPath = Path.Combine(config.TempPath, "jobs.json");
        var checklistPath = Path.Combine(config.TempPath, "jobs-checklist.csv");
        WriteJobsArtifacts(jobs, jobsJsonPath, checklistPath, config);
        logger.Info($"Render job artifacts written: {jobsJsonPath}");
        logger.Info($"Render checklist written: {checklistPath}");

        var sourceByJob = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var job in jobs)
        {
            var source = FindStagedSource(config.RenderStagingPath, job);
            if (source is not null)
            {
                sourceByJob[job.JobKey] = source;
                logger.Verbose($"WMVx staged source found for {job.JobKey}: {source}");
            }
            else
            {
                logger.Verbose($"WMVx staged source missing for {job.JobKey} (expected {job.OutputBaseName}.png/.jpg/.bmp/.tga in {config.RenderStagingPath})");
            }
        }

        if (options.DryRun)
        {
            logger.Info("Dry-run render phase complete (no conversion/publish writes).");
        }

        return new RenderAdapterResult(sourceByJob, new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase));
    }

    private static string? FindStagedSource(string stagingPath, RenderJob job)
    {
        var preferredPath = Path.Combine(stagingPath, job.ExpectedStagingFileName);
        if (File.Exists(preferredPath)) return preferredPath;

        return FindStagedSource(stagingPath, job.OutputBaseName);
    }

    private static string? FindStagedSource(string stagingPath, string baseName)
    {
        foreach (var ext in SupportedStagingExtensions)
        {
            var path = Path.Combine(stagingPath, baseName + ext);
            if (File.Exists(path)) return path;
        }
        return null;
    }

    private static void WriteJobsArtifacts(IReadOnlyList<RenderJob> jobs, string jsonPath, string csvPath, AppConfig config)
    {
        var dto = jobs.Select(j => new
        {
            key = j.JobKey,
            manifestKey = j.ManifestKey,
            reason = j.Reason,
            baseName = j.OutputBaseName,
            expectedStagingFilename = j.ExpectedStagingFileName,
            expectedStagingFiles = SupportedStagingExtensions.Select(ext => j.OutputBaseName + ext).ToArray(),
            expectedStagingOutputPath = Path.Combine(config.RenderStagingPath, j.ExpectedStagingFileName),
            finalAddonFilename = j.FinalAddonFilename,
            finalAddonImagePath = j.FinalAddonImagePath,
            finalOutputPath = j.FinalOutputPath,
            modelInputs = new
            {
                j.Character.Race,
                j.Character.Gender,
                gearItemIds = CharacterRecord.GearSlots.ToDictionary(slot => slot, slot => j.Character.GearItemIds.TryGetValue(slot, out var id) ? id : 0)
            },
            character = new
            {
                j.Character.Name,
                j.Character.Realm,
                j.Character.Account,
                j.Character.Faction,
                j.Character.Race,
                j.Character.Gender,
                j.Character.Class,
                j.Character.Level,
                j.Character.LastUpdateEpoch,
                gearItemIds = CharacterRecord.GearSlots.ToDictionary(slot => slot, slot => j.Character.GearItemIds.TryGetValue(slot, out var id) ? id : 0),
                gearItemLinks = CharacterRecord.GearSlots.ToDictionary(slot => slot, slot => j.Character.GearLinks.TryGetValue(slot, out var link) ? link : "")
            },
            renderSpec = new
            {
                width = config.RenderSpec.Width,
                height = config.RenderSpec.Height,
                preferTransparentBackground = config.RenderSpec.PreferTransparentBackground,
                backgroundColorFallback = config.RenderSpec.BackgroundColorFallback,
                framingPreset = config.RenderSpec.FramingPreset
            },
            wmvxPolicy = new
            {
                preferredClientProfile = config.WmvxPolicy.PreferredClientProfile,
                fallbackClientProfile = config.WmvxPolicy.FallbackClientProfile,
                allowAnyWorkingClientProfile = config.WmvxPolicy.AllowAnyWorkingClientProfile,
                missingItemPolicy = config.WmvxPolicy.MissingItemPolicy,
                placeholderLabel = config.WmvxPolicy.PlaceholderLabel
            }
        });

        File.WriteAllText(jsonPath, JsonSerializer.Serialize(dto, new JsonSerializerOptions { WriteIndented = true }));

        var sb = new StringBuilder();
        sb.AppendLine("ManifestKey,Reason,Realm,Account,Character,Faction,Class,Race,Gender,Level,LastUpdateEpoch,GearHash,RenderMode,FramingPreset,RenderWidth,RenderHeight,PreferTransparentBackground,BackgroundColorFallback,PreferredClientProfile,FallbackClientProfile,AllowAnyWorkingClientProfile,MissingItemPolicy,PlaceholderLabel,ExpectedStagingFilename,FinalAddonFilename,FinalAddonImagePath,FinalOutputPath,GearItemIds,GearItemLinks");
        foreach (var j in jobs)
        {
            var gearIds = string.Join("|", CharacterRecord.GearSlots.Select(slot => $"{slot}:{(j.Character.GearItemIds.TryGetValue(slot, out var id) ? id : 0)}"));
            var gearLinks = string.Join("|", CharacterRecord.GearSlots.Select(slot => $"{slot}:{(j.Character.GearLinks.TryGetValue(slot, out var link) ? link : "")}"));
            sb.AppendLine(
                $"\"{Escape(j.JobKey)}\",\"{Escape(j.Reason)}\",\"{Escape(j.Character.Realm)}\",\"{Escape(j.Character.Account)}\",\"{Escape(j.Character.Name)}\",\"{Escape(j.Character.Faction)}\",\"{Escape(j.Character.Class)}\",\"{Escape(j.Character.Race)}\",\"{Escape(j.Character.Gender)}\",\"{j.Character.Level}\",\"{j.Character.LastUpdateEpoch}\",\"{Escape(j.GearHash)}\",\"{Escape(config.RenderMode)}\",\"{Escape(config.RenderSpec.FramingPreset)}\",\"{config.RenderSpec.Width}\",\"{config.RenderSpec.Height}\",\"{config.RenderSpec.PreferTransparentBackground}\",\"{Escape(config.RenderSpec.BackgroundColorFallback)}\",\"{Escape(config.WmvxPolicy.PreferredClientProfile)}\",\"{Escape(config.WmvxPolicy.FallbackClientProfile)}\",\"{config.WmvxPolicy.AllowAnyWorkingClientProfile}\",\"{Escape(config.WmvxPolicy.MissingItemPolicy)}\",\"{Escape(config.WmvxPolicy.PlaceholderLabel)}\",\"{Escape(j.ExpectedStagingFileName)}\",\"{Escape(j.FinalAddonFilename)}\",\"{Escape(j.FinalAddonImagePath)}\",\"{Escape(j.FinalOutputPath)}\",\"{Escape(gearIds)}\",\"{Escape(gearLinks)}\"");
        }
        File.WriteAllText(csvPath, sb.ToString());
    }

    private static string Escape(string value) => value.Replace("\"", "\"\"");
}
