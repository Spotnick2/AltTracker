using AltTracker.RenderPipeline.Infrastructure;

namespace AltTracker.RenderPipeline.Services.HeroShot;

/// <summary>
/// Uses the resolved reference image as the hero-shot source without generation.
/// This allows manual PNG/JPG/TGA imports to flow through the same cover-crop
/// conversion and manifest publish pipeline as generated shots.
/// </summary>
public sealed class ManualHeroShotProvider : IHeroShotRenderProvider
{
    public string ProviderId => "manual";

    public ManualHeroShotProvider(AppConfig.HeroShotConfig _, RunLogger __)
    {
    }

    public Task<HeroShotResponse> GenerateAsync(HeroShotRequest request, CancellationToken cancellationToken = default)
    {
        if (request.ReferenceImageBytes is not { Length: > 0 })
        {
            return Task.FromResult(new HeroShotResponse
            {
                Success = false,
                Error = "Manual hero-shot provider requires a reference image file (png/jpg/jpeg/tga)."
            });
        }

        return Task.FromResult(new HeroShotResponse
        {
            Success = true,
            ImageBytes = request.ReferenceImageBytes
        });
    }
}
