using AltTracker.RenderPipeline.Services.BattleNet;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;

namespace AltTracker.RenderPipeline.Tests;

/// <summary>
/// Alpha trimming is what keeps the armory render usable: the subject occupies well under 10% of
/// the 1600x1200 canvas, and skipping the trim once shipped a character at 96x189 inside a 512x896
/// frame. These pin the trim down, including the trap that made it easy to get wrong.
/// </summary>
public class TryTrimToAlphaTests
{
    /// <summary>Canvas with an opaque block at (left, top) of the given size; everything else clear.</summary>
    private static Image<Rgba32> CanvasWithSubject(
        int width, int height, int left, int top, int subjectWidth, int subjectHeight,
        Rgba32? transparentFill = null)
    {
        var image = new Image<Rgba32>(width, height, transparentFill ?? new Rgba32(0, 0, 0, 0));
        for (var y = top; y < top + subjectHeight; y++)
        {
            for (var x = left; x < left + subjectWidth; x++)
            {
                image[x, y] = new Rgba32(10, 200, 40, 255);
            }
        }
        return image;
    }

    [Fact]
    public void TrimsToTheSubjectBounds()
    {
        // Mirrors the real render's shape: a small subject on a large mostly-empty canvas.
        using var image = CanvasWithSubject(1600, 1200, 657, 383, 297, 587);

        Assert.True(ReferenceImagePreprocessor.TryTrimToAlpha(image));
        Assert.Equal(297, image.Width);
        Assert.Equal(587, image.Height);
    }

    [Fact]
    public void IgnoresColourUnderFullyTransparentPixels()
    {
        // THE trap. Transparent pixels in these renders still carry nonzero RGB, so a bounding box
        // computed over RGBA rather than the alpha channel alone covers the whole canvas and the
        // trim silently becomes a no-op.
        var colouredButClear = new Rgba32(200, 30, 90, 0);
        using var image = CanvasWithSubject(400, 300, 100, 50, 40, 60, colouredButClear);

        Assert.True(ReferenceImagePreprocessor.TryTrimToAlpha(image));
        Assert.Equal(40, image.Width);
        Assert.Equal(60, image.Height);
    }

    [Fact]
    public void ReturnsFalseForAFullyTransparentImage()
    {
        using var image = new Image<Rgba32>(64, 64, new Rgba32(0, 0, 0, 0));
        Assert.False(ReferenceImagePreprocessor.TryTrimToAlpha(image));
    }

    [Fact]
    public void ThresholdExcludesNearTransparentNoise()
    {
        using var image = CanvasWithSubject(200, 200, 80, 80, 20, 20);
        image[5, 5] = new Rgba32(255, 255, 255, 4);   // stray speck, below the default threshold

        Assert.True(ReferenceImagePreprocessor.TryTrimToAlpha(image));
        Assert.Equal(20, image.Width);
        Assert.Equal(20, image.Height);
    }

    [Fact]
    public void ThresholdIsHonouredWhenLowered()
    {
        using var image = CanvasWithSubject(200, 200, 80, 80, 20, 20);
        image[5, 5] = new Rgba32(255, 255, 255, 4);

        // With a threshold below the speck's alpha it counts, widening the box up and left.
        Assert.True(ReferenceImagePreprocessor.TryTrimToAlpha(image, alphaThreshold: 1));
        Assert.Equal(95, image.Width);   // 80 + 20 - 5
        Assert.Equal(95, image.Height);
    }

    [Fact]
    public void AlreadyTightImageIsUnchanged()
    {
        using var image = CanvasWithSubject(30, 40, 0, 0, 30, 40);
        Assert.True(ReferenceImagePreprocessor.TryTrimToAlpha(image));
        Assert.Equal(30, image.Width);
        Assert.Equal(40, image.Height);
    }
}

public class LooksLikePngTests
{
    [Fact]
    public void AcceptsThePngSignature()
    {
        byte[] png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01];
        Assert.True(ReferenceImagePreprocessor.LooksLikePng(png));
    }

    [Fact]
    public void RejectsOtherContent()
    {
        byte[] jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46];
        byte[] html = "<!doctype html>"u8.ToArray();

        Assert.False(ReferenceImagePreprocessor.LooksLikePng(jpeg));
        Assert.False(ReferenceImagePreprocessor.LooksLikePng(html));
        Assert.False(ReferenceImagePreprocessor.LooksLikePng([0x89, 0x50]));
        Assert.False(ReferenceImagePreprocessor.LooksLikePng([]));
    }
}
