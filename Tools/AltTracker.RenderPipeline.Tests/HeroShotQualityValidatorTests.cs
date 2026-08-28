using AltTracker.RenderPipeline.Services.HeroShot;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats.Png;
using SixLabors.ImageSharp.PixelFormats;

namespace AltTracker.RenderPipeline.Tests;

/// <summary>
/// Last gate before a generated image is staged and published. It exists because a failed
/// generation can still return bytes — a blank canvas or a truncated file — and publishing that
/// would overwrite a good portrait with an empty one.
/// </summary>
public class HeroShotQualityValidatorTests
{
    private static byte[] PngOf(int width, int height, Func<int, int, Rgba32> pixel)
    {
        using var image = new Image<Rgba32>(width, height);
        for (var y = 0; y < height; y++)
        {
            for (var x = 0; x < width; x++)
            {
                image[x, y] = pixel(x, y);
            }
        }
        using var buffer = new MemoryStream();
        image.Save(buffer, new PngEncoder());
        return buffer.ToArray();
    }

    private static byte[] VariedPng(int width, int height) =>
        PngOf(width, height, (x, y) => new Rgba32(
            (byte)((x * 7) % 256), (byte)((y * 13) % 256), (byte)((x + y) % 256), 255));

    [Fact]
    public void AcceptsAVariedImageOfWorkableSize()
    {
        var result = new HeroShotQualityValidator().Validate(VariedPng(512, 896));
        Assert.True(result.IsValid, result.Reason);
    }

    [Fact]
    public void RejectsAUniformCanvas()
    {
        // The failure this is really guarding: a generation that came back blank.
        var result = new HeroShotQualityValidator()
            .Validate(PngOf(512, 896, (_, _) => new Rgba32(18, 18, 18, 255)));

        Assert.False(result.IsValid);
        Assert.False(string.IsNullOrWhiteSpace(result.Reason));
    }

    [Fact]
    public void RejectsAnImageBelowTheMinimumSize()
        => Assert.False(new HeroShotQualityValidator().Validate(VariedPng(32, 32)).IsValid);

    [Fact]
    public void RejectsTruncatedAndEmptyPayloads()
    {
        var validator = new HeroShotQualityValidator();

        Assert.False(validator.Validate([]).IsValid);
        Assert.False(validator.Validate([0x89, 0x50, 0x4E, 0x47]).IsValid);          // header only
        Assert.False(validator.Validate(VariedPng(512, 896)[..64]).IsValid);         // cut short
        Assert.False(validator.Validate("not an image at all"u8.ToArray()).IsValid);
    }

    [Fact]
    public void IsDeterministic()
    {
        // Sampling uses a fixed seed, so the same bytes must always reach the same verdict.
        var bytes = VariedPng(256, 256);
        var validator = new HeroShotQualityValidator();

        Assert.Equal(validator.Validate(bytes).IsValid, validator.Validate(bytes).IsValid);
    }
}
