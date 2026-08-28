namespace AltTracker.RenderPipeline.Infrastructure;

public sealed class CliOptions
{
    public bool DryRun { get; set; }
    public bool ForceAll { get; set; }
    public bool Verbose { get; set; }
    public bool InteractiveSelection { get; set; }
    /// <summary>
    /// Check the armory for updated character renders and queue any that changed.
    ///
    /// Required because RenderPlanner drops unchanged characters before the render adapter runs, so
    /// a render that changed remotely (the player logged out in new gear) with no local
    /// SavedVariables change could otherwise never produce a job. Opt-in so ordinary runs stay
    /// offline and cheap.
    /// </summary>
    public bool RefreshArmory { get; set; }
    public int? MaxJobs { get; set; }
    public int? MaxAgeDaysOverride { get; set; }
    public string? ConfigPath { get; set; }
    public string? InputPath { get; set; }
    public string? OutputDirectory { get; set; }
    public string? AddonMediaDirectory { get; set; }
    public string? ManifestPath { get; set; }
    public string? StagingDirectory { get; set; }
    public string? TempDirectory { get; set; }
    public string? ConverterPath { get; set; }
    public string? RenderBackend { get; set; }
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
                case "--refresh-armory":
                    o.RefreshArmory = true;
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
              --refresh-armory (check Battle.net for updated character renders)
              --interactive (choose all vs selected vs stale-only)
              --character <realm:account:name> (repeatable)
              --verbose
              --config <path>
              --input <path>
              --output <dir>
              --addon-media <dir>
              --manifest <path>
              --staging <dir>
              --temp <dir>
              --converter <path-or-command>
              --render-backend <HeroShot>
              --heroshot-style <realistic|wow-like|cartoonish>
              --max-jobs <n>
              --max-age-days <n>
            """);
    }
}
