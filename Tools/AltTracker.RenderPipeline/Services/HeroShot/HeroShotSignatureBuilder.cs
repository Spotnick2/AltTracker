using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Models;

namespace AltTracker.RenderPipeline.Services.HeroShot;

public static class HeroShotSignatureBuilder
{
    public static string Compute(CharacterRecord character, AppConfig.HeroShotConfig cfg)
    {
        var gearEntries = CharacterRecord.GearSlots
            .Select(slot => $"{slot}:{character.GearItemIds.GetValueOrDefault(slot, 0)}")
            .ToArray();

        var canonical = new Dictionary<string, object>(StringComparer.Ordinal)
        {
            ["identity"] = $"{character.Realm}/{character.Account}/{character.Name}",
            ["race"] = character.Race ?? "",
            ["gender"] = character.Gender ?? "",
            ["class"] = character.Class ?? "",
            ["gear"] = gearEntries,
            ["style"] = cfg.Style ?? "realistic",
            ["promptTemplateVersion"] = cfg.PromptTemplateVersion ?? "v1",
            ["generationVersion"] = cfg.GenerationVersion ?? "1",
            ["provider"] = cfg.Provider ?? "openai",
            ["model"] = cfg.Model ?? "gpt-image-1",
            ["width"] = cfg.Width,
            ["height"] = cfg.Height,
            ["generationOutputFormat"] = cfg.OutputFormat ?? "png",
            ["outputWidth"] = cfg.OutputWidth,
            ["outputHeight"] = cfg.OutputHeight,
            ["cropMode"] = cfg.CropMode ?? "cover",
            ["anchor"] = cfg.Anchor ?? "center",
            ["format"] = cfg.Format ?? "tga",
        };

        var json = JsonSerializer.Serialize(canonical, new JsonSerializerOptions
        {
            WriteIndented = false,
            PropertyNamingPolicy = null
        });
        var bytes = Encoding.UTF8.GetBytes(json);
        var hash = SHA256.HashData(bytes);
        return "hs1:" + Convert.ToHexString(hash).ToLowerInvariant();
    }

    public static string ComputeFileFingerprint(string filePath)
    {
        if (!File.Exists(filePath)) return "";
        var bytes = File.ReadAllBytes(filePath);
        var hash = SHA256.HashData(bytes);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
}
