namespace AltTracker.RenderPipeline.Services.HeroShot;

public sealed class HeroShotRequest
{
    public required string IdempotencyKey { get; init; }
    public required string Prompt { get; init; }
    public required string StylePreset { get; init; }
    public int Width { get; init; } = 1024;
    public int Height { get; init; } = 1024;
    public byte[]? ReferenceImageBytes { get; init; }
    public string ReferenceImageName { get; init; } = "reference.png";
    /// <summary>
    /// Raw Battle.net armory render (transparent PNG) for this character, when one exists.
    /// Only the "armory" provider consumes it; it is the render itself, not the gray-composited
    /// reference that is fed to the image model.
    /// </summary>
    public byte[]? ArmoryRenderBytes { get; init; }
}
