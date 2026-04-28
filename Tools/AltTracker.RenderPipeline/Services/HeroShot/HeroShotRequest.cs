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
}
