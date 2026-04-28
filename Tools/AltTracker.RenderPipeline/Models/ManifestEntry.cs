namespace AltTracker.RenderPipeline.Models;

public sealed class ManifestEntry
{
    public string Image { get; init; } = "";
    public string GeneratedAt { get; init; } = "";
    public string GearHash { get; init; } = "";
    public string Mode { get; init; } = "";
    public string Width { get; init; } = "";
    public string Height { get; init; } = "";
    public string Style { get; init; } = "";
    public string Signature { get; init; } = "";

    public static ManifestEntry FromJob(RenderJob job, Infrastructure.AppConfig config)
    {
        var mode = config.RenderBackend.Equals("HeroShot", StringComparison.OrdinalIgnoreCase)
            ? "heroshot"
            : config.RenderMode;
        return new ManifestEntry
        {
            Image = job.FinalAddonImagePath,
            GeneratedAt = DateTimeOffset.UtcNow.ToString("O"),
            GearHash = job.GearHash,
            Mode = mode,
            Width = config.RenderSpec.Width.ToString(),
            Height = config.RenderSpec.Height.ToString(),
            Style = config.RenderBackend.Equals("HeroShot", StringComparison.OrdinalIgnoreCase)
                ? (config.HeroShot.Style ?? "")
                : "",
            Signature = job.GearHash
        };
    }
}
