using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Services.BattleNet;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;

namespace AltTracker.RenderPipeline.Services.HeroShot;

/// <summary>
/// Publishes the Battle.net armory render directly as the hero shot, with no AI generation.
///
/// Exact gear and zero generation cost, at the price of fidelity: these are 2007-era character
/// models, so the subject is only a few hundred pixels tall and looks low-poly when scaled up to
/// hero size. Codex remains the default; this is opt-in per character or globally.
/// </summary>
public sealed class ArmoryHeroShotProvider : IHeroShotRenderProvider
{
    private readonly AppConfig.HeroShotConfig _cfg;
    private readonly RunLogger _logger;

    public string ProviderId => "armory";

    public ArmoryHeroShotProvider(AppConfig.HeroShotConfig cfg, RunLogger logger)
    {
        _cfg = cfg;
        _logger = logger;
    }

    public Task<HeroShotResponse> GenerateAsync(HeroShotRequest request, CancellationToken cancellationToken = default)
    {
        if (request.ArmoryRenderBytes is not { Length: > 0 })
        {
            return Task.FromResult(new HeroShotResponse
            {
                Success = false,
                Error = "No armory render available for this character. Battle.net has no full-body "
                      + "render for it - most often because it is below level 10, which Blizzard "
                      + "does not render at all; otherwise it has never logged out since renders "
                      + "were enabled, or was renamed. Set this character back to the 'codex' "
                      + "provider, or check --refresh-armory output."
            });
        }

        try
        {
            using var source = Image.Load<Rgba32>(request.ArmoryRenderBytes);

            // Trim the mostly-empty canvas FIRST. These bytes are the raw 1600x1200 render in which
            // the subject occupies under 10% of the pixels; fitting it untrimmed would scale the
            // character to roughly a fifth of the frame height and publish a tiny floating figure.
            if (!ReferenceImagePreprocessor.TryTrimToAlpha(source))
            {
                return Task.FromResult(new HeroShotResponse
                {
                    Success = false,
                    Error = "Armory render contained no visible pixels."
                });
            }

            // Fit the whole character into the target frame. The publish step crops with "cover",
            // which would cut off head and feet - emitting the final size here makes that a no-op.
            var targetWidth = Math.Max(64, _cfg.OutputWidth);
            var targetHeight = Math.Max(64, _cfg.OutputHeight);

            using var fitted = source.Clone(x => x.Resize(new ResizeOptions
            {
                Size = new Size(targetWidth, targetHeight),
                Mode = ResizeMode.Pad,
                Position = AnchorPositionMode.Center,
                PadColor = Color.Transparent,
                Sampler = KnownResamplers.Lanczos3
            }));

            using var buffer = new MemoryStream();
            fitted.SaveAsPng(buffer);

            _logger.Info($"[HeroShot] Armory render fitted to {targetWidth}x{targetHeight} (no generation).");
            return Task.FromResult(new HeroShotResponse
            {
                Success = true,
                ImageBytes = buffer.ToArray()
            });
        }
        catch (Exception ex)
        {
            return Task.FromResult(new HeroShotResponse
            {
                Success = false,
                Error = $"Failed to prepare the armory render: {ex.Message}"
            });
        }
    }
}
