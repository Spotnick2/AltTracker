namespace AltTracker.RenderPipeline.Services.HeroShot;

public sealed class HeroShotResponse
{
    public bool Success { get; init; }
    public byte[]? ImageBytes { get; init; }
    public string? Error { get; init; }
    public string? RevisedPrompt { get; init; }
}
