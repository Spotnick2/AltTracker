using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Models;

namespace AltTracker.RenderPipeline.Services.HeroShot;

public static class HeroShotSignatureBuilder
{
    /// <param name="referenceFingerprint">
    /// Hash of the reference image actually used. Part of the signature because the reference now
    /// refreshes itself from the armory: without it, a character who logs out in new gear would
    /// keep the old portrait forever, since nothing else in the signature would have changed.
    /// </param>
    /// <param name="effectiveProvider">
    /// The provider actually used for this character, which may differ from cfg.Provider because of
    /// a per-character override. Hashing the global default instead would mean flipping one
    /// character between codex and armory did not invalidate its cached render.
    /// </param>
    public static string Compute(
        CharacterRecord character, AppConfig.HeroShotConfig cfg, string referenceFingerprint = "",
        string? effectiveProvider = null)
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
            ["provider"] = effectiveProvider ?? cfg.Provider ?? "codex",
            ["model"] = cfg.Model ?? "gpt-image-1",
            ["width"] = cfg.Width,
            ["height"] = cfg.Height,
            ["generationOutputFormat"] = cfg.OutputFormat ?? "png",
            ["outputWidth"] = cfg.OutputWidth,
            ["outputHeight"] = cfg.OutputHeight,
            ["cropMode"] = cfg.CropMode ?? "cover",
            ["anchor"] = cfg.Anchor ?? "center",
            ["format"] = cfg.Format ?? "tga",
            ["referenceFingerprint"] = referenceFingerprint ?? "",
        };

        // Only present when a slot is actually hidden. Adding these unconditionally would change
        // every existing signature and force a full re-render of the whole roster; keyed this way,
        // only characters whose portrait would actually differ get invalidated. Flipping the toggle
        // in game still adds or removes the key, which is what makes the re-render happen.
        // The codex driver model materially changes the portrait (it reads the reference and writes
        // the image prompt), so switching it must invalidate cached renders the same way a style or
        // reference change does. Written only when pinned, so an empty setting keeps prior signatures.
        if (!string.IsNullOrWhiteSpace(cfg.Codex?.Model))
            canonical["codexModel"] = cfg.Codex.Model.Trim();

        if (!character.ShowHelm) canonical["hideHelm"] = true;
        if (!character.ShowCloak) canonical["hideCloak"] = true;

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
