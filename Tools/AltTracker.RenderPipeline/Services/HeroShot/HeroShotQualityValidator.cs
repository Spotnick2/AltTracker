using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;

namespace AltTracker.RenderPipeline.Services.HeroShot;

public sealed class HeroShotQualityValidator
{
    public sealed class ValidationResult
    {
        public bool IsValid { get; init; }
        public string? Reason { get; init; }
    }

    public ValidationResult Validate(byte[] imageBytes)
    {
        if (imageBytes is null || imageBytes.Length < 100)
            return new ValidationResult { IsValid = false, Reason = "image bytes too small or null" };

        Image<Rgba32> image;
        try
        {
            image = Image.Load<Rgba32>(imageBytes);
        }
        catch (Exception ex)
        {
            return new ValidationResult { IsValid = false, Reason = $"image decode failed: {ex.Message}" };
        }

        using (image)
        {
            if (image.Width < 64 || image.Height < 64)
                return new ValidationResult { IsValid = false, Reason = $"image too small: {image.Width}x{image.Height}" };

            var rng = new Random(42);
            var samples = new List<Rgba32>();
            for (var i = 0; i < 200; i++)
            {
                var x = rng.Next(image.Width);
                var y = rng.Next(image.Height);
                samples.Add(image[x, y]);
            }

            var minR = samples.Min(p => p.R);
            var maxR = samples.Max(p => p.R);
            var minG = samples.Min(p => p.G);
            var maxG = samples.Max(p => p.G);
            var minB = samples.Min(p => p.B);
            var maxB = samples.Max(p => p.B);

            var rangeR = maxR - minR;
            var rangeG = maxG - minG;
            var rangeB = maxB - minB;

            if (rangeR <= 10 && rangeG <= 10 && rangeB <= 10)
                return new ValidationResult { IsValid = false, Reason = $"image appears blank/uniform (R={rangeR}, G={rangeG}, B={rangeB})" };
        }

        return new ValidationResult { IsValid = true };
    }
}
