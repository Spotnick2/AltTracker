namespace AltTracker.RenderPipeline.Services.HeroShot;

public interface IHeroShotRenderProvider
{
    string ProviderId { get; }
    Task<HeroShotResponse> GenerateAsync(HeroShotRequest request, CancellationToken cancellationToken = default);
}
