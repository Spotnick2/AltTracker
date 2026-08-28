using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;

namespace AltTracker.RenderPipeline.Services.BattleNet;

/// <summary>
/// Turns a raw Blizzard render into a reference image suitable for the image model.
///
/// The raw render is a 1600x1200 canvas in which the character occupies roughly 9% of the pixels
/// (measured: 297x587). Sent untrimmed it wastes the model's attention on empty space, so it is
/// trimmed to the alpha bounding box, padded slightly, and flattened onto an opaque backdrop.
/// </summary>
public static class ReferenceImagePreprocessor
{
    private static readonly byte[] PngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    public static bool LooksLikePng(ReadOnlySpan<byte> bytes)
        => bytes.Length >= PngMagic.Length && bytes[..PngMagic.Length].SequenceEqual(PngMagic);

    /// <summary>
    /// Reads <paramref name="sourcePath"/>, trims to the alpha bbox, pads, flattens onto
    /// <paramref name="backgroundHex"/> and writes a PNG to <paramref name="destinationPath"/>.
    /// Returns false when the render has no visible subject.
    /// </summary>
    public static bool TryPrepare(
        string sourcePath,
        string destinationPath,
        string backgroundHex,
        double paddingFraction,
        int alphaThreshold,
        int targetWidth,
        int targetHeight,
        RunLogger logger)
    {
        try
        {
            using var image = Image.Load<Rgba32>(sourcePath);

            var bbox = FindAlphaBounds(image, (byte)Math.Clamp(alphaThreshold, 0, 255));
            if (bbox is null)
            {
                logger.Warn($"[BattleNet] Render has no visible pixels above the alpha threshold: {sourcePath}");
                return false;
            }

            var (left, top, right, bottom) = bbox.Value;
            var cropWidth = right - left + 1;
            var cropHeight = bottom - top + 1;

            using var cropped = image.Clone(x => x.Crop(new Rectangle(left, top, cropWidth, cropHeight)));

            // Pad so hair, weapons and feet do not sit flush against the frame edge.
            var padX = (int)Math.Round(cropWidth * Math.Clamp(paddingFraction, 0, 0.5));
            var padY = (int)Math.Round(cropHeight * Math.Clamp(paddingFraction, 0, 0.5));
            var canvasWidth = cropWidth + (padX * 2);
            var canvasHeight = cropHeight + (padY * 2);

            var background = ParseColor(backgroundHex);

            using var canvas = new Image<Rgba32>(canvasWidth, canvasHeight);
            canvas.Mutate(x => x.BackgroundColor(background));
            canvas.Mutate(x => x.DrawImage(cropped, new Point(padX, padY), 1f));

            // Upscale to the generation size. The trimmed subject is only a few hundred pixels
            // tall; handing the model a reference at the size it is being asked to generate gives it
            // a far clearer view of the gear than the native crop does.
            var finalWidth = canvasWidth;
            var finalHeight = canvasHeight;
            if (targetWidth > 0 && targetHeight > 0)
            {
                canvas.Mutate(x => x.Resize(new ResizeOptions
                {
                    Size = new Size(targetWidth, targetHeight),
                    Mode = ResizeMode.Pad,
                    Position = AnchorPositionMode.Center,
                    PadColor = background,
                    Sampler = KnownResamplers.Lanczos3
                }));
                finalWidth = targetWidth;
                finalHeight = targetHeight;
            }

            Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);
            var tempPath = destinationPath + ".tmp";
            canvas.SaveAsPng(tempPath);
            File.Move(tempPath, destinationPath, overwrite: true);

            logger.Verbose(
                $"[BattleNet] Reference prepared: {image.Width}x{image.Height} -> subject {cropWidth}x{cropHeight} "
              + $"-> {canvasWidth}x{canvasHeight} -> {finalWidth}x{finalHeight} on {backgroundHex}");
            return true;
        }
        catch (Exception ex)
        {
            logger.Warn($"[BattleNet] Failed to prepare reference from {sourcePath}: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Bounding box of pixels whose ALPHA exceeds the threshold.
    ///
    /// Deliberately alpha-only: fully transparent pixels in these renders can still carry nonzero
    /// RGB, so an RGBA-wide bounding box would cover the entire canvas and the trim would be a no-op.
    /// </summary>
    private static (int Left, int Top, int Right, int Bottom)? FindAlphaBounds(Image<Rgba32> image, byte alphaThreshold)
    {
        var left = int.MaxValue;
        var top = int.MaxValue;
        var right = int.MinValue;
        var bottom = int.MinValue;

        image.ProcessPixelRows(accessor =>
        {
            for (var y = 0; y < accessor.Height; y++)
            {
                var row = accessor.GetRowSpan(y);
                for (var x = 0; x < row.Length; x++)
                {
                    if (row[x].A <= alphaThreshold) continue;

                    if (x < left) left = x;
                    if (x > right) right = x;
                    if (y < top) top = y;
                    if (y > bottom) bottom = y;
                }
            }
        });

        if (right < left || bottom < top) return null;
        return (left, top, right, bottom);
    }

    private static Color ParseColor(string hex)
    {
        try
        {
            return Color.ParseHex(hex);
        }
        catch
        {
            return Color.FromRgb(0x80, 0x80, 0x80);
        }
    }
}
