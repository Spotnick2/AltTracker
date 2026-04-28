namespace AltTracker.RenderPipeline.Services.HeroShot;

public sealed class HeroShotRenderState
{
    public string ManifestKey { get; set; } = "";
    public string RenderSignature { get; set; } = "";
    public string StylePreset { get; set; } = "";
    public string ProviderId { get; set; } = "";
    public string ProviderModel { get; set; } = "";
    public string PromptTemplateVersion { get; set; } = "";
    public string GenerationVersion { get; set; } = "";
    public int Width { get; set; }
    public int Height { get; set; }
    public string OutputFormat { get; set; } = "";
    public string GeneratedAt { get; set; } = "";
    public string ReferenceFingerprint { get; set; } = "";
}
