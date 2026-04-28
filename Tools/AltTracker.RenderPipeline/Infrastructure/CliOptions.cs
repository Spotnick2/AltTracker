namespace AltTracker.RenderPipeline.Infrastructure;

public sealed class CliOptions
{
    public bool DryRun { get; set; }
    public bool ForceAll { get; set; }
    public bool Verbose { get; set; }
    public bool InteractiveSelection { get; set; }
    public int? MaxJobs { get; set; }
    public int? MaxAgeDaysOverride { get; set; }
    public string? ConfigPath { get; set; }
    public string? InputPath { get; set; }
    public string? OutputDirectory { get; set; }
    public string? AddonMediaDirectory { get; set; }
    public string? ManifestPath { get; set; }
    public string? WmvxPath { get; set; }
    public string? StagingDirectory { get; set; }
    public string? TempDirectory { get; set; }
    public string? ConverterPath { get; set; }
    public string? RenderBackend { get; set; }
    public string? ConverterUrl { get; set; }
    public string? WowExportUrl { get; set; }
    public string? ExportedAssetsPath { get; set; }
    public string? NodePath { get; set; }
    public string? NpmPath { get; set; }
    public string? NpxPath { get; set; }
    public string? PlaywrightScriptPath { get; set; }
    public string? CaptureTarget { get; set; }
    public string? ConverterInputFallback { get; set; }
    public int? ExportTimeoutSeconds { get; set; }
    public int? ViewerTimeoutSeconds { get; set; }
    public int? ScreenshotWidth { get; set; }
    public int? ScreenshotHeight { get; set; }
    public HashSet<string> CharacterFilters { get; } = new(StringComparer.OrdinalIgnoreCase);
    public string? HeroShotStyle { get; set; }

    public static CliOptions Parse(string[] args)
    {
        var o = new CliOptions();
        for (var i = 0; i < args.Length; i++)
        {
            var arg = args[i];
            switch (arg)
            {
                case "--dry-run":
                    o.DryRun = true;
                    break;
                case "--force-all":
                    o.ForceAll = true;
                    break;
                case "--verbose":
                    o.Verbose = true;
                    break;
                case "--interactive":
                case "--select-chars":
                    o.InteractiveSelection = true;
                    break;
                case "--max-jobs":
                    o.MaxJobs = ReadInt(args, ref i, "--max-jobs");
                    break;
                case "--max-age-days":
                    o.MaxAgeDaysOverride = ReadInt(args, ref i, "--max-age-days");
                    break;
                case "--config":
                    o.ConfigPath = ReadString(args, ref i, "--config");
                    break;
                case "--input":
                    o.InputPath = ReadString(args, ref i, "--input");
                    break;
                case "--output":
                    o.OutputDirectory = ReadString(args, ref i, "--output");
                    break;
                case "--addon-media":
                    o.AddonMediaDirectory = ReadString(args, ref i, "--addon-media");
                    break;
                case "--manifest":
                    o.ManifestPath = ReadString(args, ref i, "--manifest");
                    break;
                case "--wmvx":
                    o.WmvxPath = ReadString(args, ref i, "--wmvx");
                    break;
                case "--staging":
                    o.StagingDirectory = ReadString(args, ref i, "--staging");
                    break;
                case "--temp":
                    o.TempDirectory = ReadString(args, ref i, "--temp");
                    break;
                case "--converter":
                    o.ConverterPath = ReadString(args, ref i, "--converter");
                    break;
                case "--render-backend":
                    o.RenderBackend = ReadString(args, ref i, "--render-backend");
                    break;
                case "--converter-url":
                    o.ConverterUrl = ReadString(args, ref i, "--converter-url");
                    break;
                case "--wowexport-url":
                    o.WowExportUrl = ReadString(args, ref i, "--wowexport-url");
                    break;
                case "--exported-assets":
                    o.ExportedAssetsPath = ReadString(args, ref i, "--exported-assets");
                    break;
                case "--node":
                    o.NodePath = ReadString(args, ref i, "--node");
                    break;
                case "--npm":
                    o.NpmPath = ReadString(args, ref i, "--npm");
                    break;
                case "--npx":
                    o.NpxPath = ReadString(args, ref i, "--npx");
                    break;
                case "--playwright-script":
                    o.PlaywrightScriptPath = ReadString(args, ref i, "--playwright-script");
                    break;
                case "--capture-target":
                    o.CaptureTarget = ReadString(args, ref i, "--capture-target");
                    break;
                case "--converter-input-fallback":
                    o.ConverterInputFallback = ReadString(args, ref i, "--converter-input-fallback");
                    break;
                case "--export-timeout":
                    o.ExportTimeoutSeconds = ReadInt(args, ref i, "--export-timeout");
                    break;
                case "--viewer-timeout":
                    o.ViewerTimeoutSeconds = ReadInt(args, ref i, "--viewer-timeout");
                    break;
                case "--screenshot-width":
                    o.ScreenshotWidth = ReadInt(args, ref i, "--screenshot-width");
                    break;
                case "--screenshot-height":
                    o.ScreenshotHeight = ReadInt(args, ref i, "--screenshot-height");
                    break;
                case "--character":
                    o.CharacterFilters.Add(ReadString(args, ref i, "--character"));
                    break;
                case "--heroshot-style":
                    o.HeroShotStyle = ReadString(args, ref i, "--heroshot-style");
                    break;
                case "--help":
                case "-h":
                    PrintUsage();
                    Environment.Exit((int)PipelineExitCode.Success);
                    break;
                default:
                    throw new PipelineDataException($"Unknown argument: {arg}");
            }
        }
        return o;
    }

    private static int ReadInt(string[] args, ref int i, string argName)
    {
        var raw = ReadString(args, ref i, argName);
        if (!int.TryParse(raw, out var value))
        {
            throw new PipelineDataException($"Invalid integer for {argName}: {raw}");
        }
        return value;
    }

    private static string ReadString(string[] args, ref int i, string argName)
    {
        if (i + 1 >= args.Length)
        {
            throw new PipelineDataException($"Missing value for {argName}");
        }
        i++;
        return args[i];
    }

    private static void PrintUsage()
    {
        Console.WriteLine("""
            AltTracker.RenderPipeline
            Usage:
              --dry-run
              --force-all
              --interactive (choose all vs selected vs stale-only)
              --character <realm:account:name> (repeatable)
              --verbose
              --config <path>
              --input <path>
              --output <dir>
              --addon-media <dir>
              --manifest <path>
              --wmvx <path>
              --staging <dir>
              --temp <dir>
              --converter <path-or-command>
              --render-backend <ManualWmvx|WowConverter|HeroShot>
              --heroshot-style <realistic|wow-like|cartoonish>
              --converter-url <url>
              --wowexport-url <url>
              --exported-assets <dir>
              --node <path-or-command>
              --npm <path-or-command>
              --npx <path-or-command>
              --playwright-script <path>
              --capture-target <canvas|full>
              --converter-input-fallback <url-or-input>
              --export-timeout <seconds>
              --viewer-timeout <seconds>
              --screenshot-width <pixels>
              --screenshot-height <pixels>
              --max-jobs <n>
              --max-age-days <n>
            """);
    }
}
