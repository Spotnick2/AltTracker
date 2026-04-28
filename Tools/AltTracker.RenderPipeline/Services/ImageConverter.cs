using System.Diagnostics;
using AltTracker.RenderPipeline.Infrastructure;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats.Tga;
using SixLabors.ImageSharp.Processing;
using SixLabors.ImageSharp.PixelFormats;

namespace AltTracker.RenderPipeline.Services;

public sealed class ImageConverter
{
    public ConversionResult ConvertToTga(
        string sourcePath,
        string outputPath,
        AppConfig config,
        CliOptions options,
        RunLogger logger)
    {
        try
        {
            var sourceExt = Path.GetExtension(sourcePath).ToLowerInvariant();
            if (options.DryRun)
            {
                logger.Info($"[dry-run] conversion attempted: {sourcePath} -> {outputPath}");
                return ConversionResult.Ok();
            }

            Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);

            var renderSpec = config.RenderSpec;
            var sizeToken = $"{renderSpec.Width}x{renderSpec.Height}";
            var useTransparent = renderSpec.PreferTransparentBackground;
            var background = renderSpec.BackgroundColorFallback;
            var args = useTransparent
                ? $"\"{sourcePath}\" -auto-orient -resize {sizeToken}^ -gravity center -background none -alpha set -extent {sizeToken} -compress none \"{outputPath}\""
                : $"\"{sourcePath}\" -auto-orient -resize {sizeToken}^ -gravity center -background \"{background}\" -alpha remove -alpha off -extent {sizeToken} -compress none \"{outputPath}\"";

            if (string.IsNullOrWhiteSpace(config.ConverterExecutable))
            {
                if (sourceExt == ".tga")
                {
                    File.Copy(sourcePath, outputPath, overwrite: true);
                    logger.Warn($"Converter not configured; copied source TGA without enforcing {sizeToken} render spec.");
                    logger.Info($"File written: {outputPath}");
                    return ConversionResult.Ok();
                }

                var internalConversion = ConvertWithImageSharp(sourcePath, outputPath, config, logger);
                if (internalConversion.Success)
                {
                    logger.Warn("Converter not configured; used built-in image conversion fallback.");
                }
                return internalConversion;
            }

            var psi = new ProcessStartInfo
            {
                FileName = config.ConverterExecutable,
                Arguments = args,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };

            using var process = Process.Start(psi);
            if (process is null)
            {
                return ConversionResult.Fail("Unable to start converter process.");
            }

            var stdout = process.StandardOutput.ReadToEnd();
            var stderr = process.StandardError.ReadToEnd();
            process.WaitForExit();

            if (process.ExitCode != 0)
            {
                var fallback = ConvertWithImageSharp(sourcePath, outputPath, config, logger);
                if (fallback.Success)
                {
                    logger.Warn($"Converter exited with code {process.ExitCode}; used built-in image conversion fallback.");
                    return fallback;
                }
                return ConversionResult.Fail($"Converter exited with code {process.ExitCode}. {stderr}".Trim());
            }

            if (!File.Exists(outputPath))
            {
                return ConversionResult.Fail("Converter completed but output file is missing.");
            }

            logger.Verbose($"Converter output: {stdout}");
            logger.Info($"File written: {outputPath}");
            return ConversionResult.Ok();
        }
        catch (Exception ex)
        {
            if (Path.GetExtension(sourcePath).Equals(".tga", StringComparison.OrdinalIgnoreCase))
            {
                try
                {
                    if (!options.DryRun)
                    {
                        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
                        File.Copy(sourcePath, outputPath, overwrite: true);
                        logger.Warn($"Converter unavailable ({ex.Message}); copied source TGA without normalization.");
                        logger.Info($"File written: {outputPath}");
                    }
                    return ConversionResult.Ok();
                }
                catch (Exception copyEx)
                {
                    return ConversionResult.Fail($"Converter failed and TGA fallback copy failed: {copyEx.Message}");
                }
            }

            var fallback = ConvertWithImageSharp(sourcePath, outputPath, config, logger);
            if (fallback.Success)
            {
                logger.Warn($"Converter unavailable ({ex.Message}); used built-in image conversion fallback.");
                return fallback;
            }
            return ConversionResult.Fail(ex.Message);
        }
    }

    private static ConversionResult ConvertWithImageSharp(
        string sourcePath,
        string outputPath,
        AppConfig config,
        RunLogger logger)
    {
        try
        {
            var renderSpec = config.RenderSpec;
            var width = renderSpec.Width > 0 ? renderSpec.Width : 512;
            var height = renderSpec.Height > 0 ? renderSpec.Height : 512;
            var preferTransparent = renderSpec.PreferTransparentBackground;
            var bgHex = string.IsNullOrWhiteSpace(renderSpec.BackgroundColorFallback)
                ? "#141414"
                : renderSpec.BackgroundColorFallback;

            using var source = Image.Load<Rgba32>(sourcePath);
            source.Mutate(m => m.AutoOrient());

            source.Mutate(m => m.Resize(new ResizeOptions
            {
                Size = new Size(width, height),
                Mode = ResizeMode.Crop,
                Position = AnchorPositionMode.Center,
                Sampler = KnownResamplers.Lanczos3
            }));

            if (!preferTransparent)
            {
                var background = Color.ParseHex(bgHex);
                source.Mutate(m => m.BackgroundColor(background));
            }

            Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
            source.Save(outputPath, new TgaEncoder());
            logger.Info($"File written: {outputPath}");
            return ConversionResult.Ok();
        }
        catch (Exception ex)
        {
            return ConversionResult.Fail($"Built-in conversion failed: {ex.Message}");
        }
    }
}

public sealed record ConversionResult(bool Success, string Error)
{
    public static ConversionResult Ok() => new(true, "");
    public static ConversionResult Fail(string error) => new(false, error);
}
