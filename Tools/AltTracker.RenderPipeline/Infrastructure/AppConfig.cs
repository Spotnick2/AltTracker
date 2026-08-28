using System.Text.Json;
using AltTracker.RenderPipeline.Services;

namespace AltTracker.RenderPipeline.Infrastructure;

public sealed class AppConfig
{
    public string InputDataPath { get; set; } = @"C:\Path\To\AltTracker.lua";
    public string OutputRenderDirectory { get; set; } = @"C:\Path\To\AltTracker\Media\CharacterRenders";
    public string AddonMediaDirectory { get; set; } = @"C:\Path\To\AltTracker\Media\CharacterRenders";
    public string ManifestOutputPath { get; set; } = @"C:\Path\To\AltTrackerRenderManifest.lua";
    public string RenderStagingPath { get; set; } = @"C:\Path\To\RenderStaging";
    public string TempPath { get; set; } = @"C:\Path\To\AltTrackerRenderTemp";
    public string ConverterExecutable { get; set; } = "magick";
    public string WowAddonImageRoot { get; set; } = @"Interface\AddOns\AltTracker\Media\CharacterRenders";
    public int MaxAgeDays { get; set; } = 30;
    public string RenderBackend { get; set; } = "HeroShot";
    public string RenderMode { get; set; } = "fullbody";
    public string RenderProfileVersion { get; set; } = "v1";
    public string Resolution { get; set; } = "512x512";
    public RenderSpecConfig RenderSpec { get; set; } = new();
    public HeroShotConfig HeroShot { get; set; } = new();
    public BattleNetConfig BattleNet { get; set; } = new();

    public sealed class RenderSpecConfig
    {
        public int Width { get; set; } = 512;
        public int Height { get; set; } = 512;
        public bool PreferTransparentBackground { get; set; } = true;
        public string BackgroundColorFallback { get; set; } = "#141414";
        public string FramingPreset { get; set; } = "fullbody_center_v1";
        public string PreferredStagingExtension { get; set; } = ".png";
    }

    public sealed class HeroShotConfig
    {
        public bool Enabled { get; set; } = true;
        public string Style { get; set; } = "realistic";
        public int Width { get; set; } = 1024;
        public int Height { get; set; } = 1024;
        public string OutputFormat { get; set; } = "png";
        public int OutputWidth { get; set; } = 512;
        public int OutputHeight { get; set; } = 896;
        public string CropMode { get; set; } = "cover";
        public string Anchor { get; set; } = "center";
        public string Format { get; set; } = "tga";
        public string Provider { get; set; } = "codex";
        public string Model { get; set; } = "gpt-image-1";
        public string PromptTemplateVersion { get; set; } = "v2";
        public string GenerationVersion { get; set; } = "1";
        public string ReferenceImagesPath { get; set; } = "";
        /// <summary>WoW Screenshots folder. When a character has an addon-stamped refshot_ts, the
        /// pipeline prefers the screenshot captured near that time here over the static saved reference.</summary>
        public string ScreenshotsDirectory { get; set; } = "";
        public int TimeoutSeconds { get; set; } = 120;
        public int MaxRetries { get; set; } = 2;
        public Dictionary<string, string> CharacterReferenceImages { get; set; } = new();
        /// <summary>
        /// Per-character provider override, keyed "Realm:Account:Name". Lets individual characters
        /// use the raw armory render ("armory") while the rest keep AI generation ("codex").
        /// </summary>
        public Dictionary<string, string> CharacterProviders { get; set; } = new();
        /// <summary>
        /// When true, characters without a resolved reference image are skipped rather than
        /// generating a text-only portrait. Recommended, since a reference image is essential
        /// for identity accuracy in codex imagegen.
        /// </summary>
        public bool RequireReferenceImage { get; set; } = false;
        public CodexConfig Codex { get; set; } = new();

        public sealed class CodexConfig
        {
            /// <summary>Executable name or full path of the codex CLI. On Windows a bare name is an
            /// npm .cmd shim, resolved via cmd.exe; a value containing a path or ending in .exe runs directly.</summary>
            public string CodexExecutable { get; set; } = "codex";
            /// <summary>Reasoning effort for `codex exec` (low|medium|high). Image generation needs little reasoning.</summary>
            public string ReasoningEffort { get; set; } = "low";
            /// <summary>Hard timeout for a single codex generation, in seconds. Built-in image_gen
            /// commonly takes 2–4 minutes, so keep comfortable margin (no retry happens on timeout).</summary>
            public int TimeoutSeconds { get; set; } = 360;
            /// <summary>Optional extra args appended to `codex exec` (advanced; e.g. `-m &lt;model&gt;`).</summary>
            public string ExtraArgs { get; set; } = "";
            /// <summary>When true, enables codex's web-search tool (`-c web_search=live`) so it can look up
            /// each named item's real in-game appearance (e.g. on Wowhead) before generating. More accurate
            /// transmog, but adds a browsing step per render and consumes OpenAI usage. Default off.</summary>
            public bool EnableWebSearch { get; set; } = false;
        }
    }

    /// <summary>
    /// Battle.net API settings for sourcing character renders from the armory.
    ///
    /// Credentials are deliberately absent: appsettings.json is git-tracked, so the client secret
    /// comes from the environment only (see BattleNetCredentials).
    /// </summary>
    public sealed class BattleNetConfig
    {
        public bool Enabled { get; set; } = false;
        /// <summary>API region host prefix, e.g. "us" -> us.api.blizzard.com. Single region per run.</summary>
        public string Region { get; set; } = "us";
        /// <summary>Profile namespace. Anniversary realms use classicann-{region}.</summary>
        public string Namespace { get; set; } = "profile-classicann-us";
        /// <summary>Namespace for the realm index, used to resolve canonical realm slugs.</summary>
        public string RealmNamespace { get; set; } = "dynamic-classicann-us";
        public int TimeoutSeconds { get; set; } = 30;
        /// <summary>Where cached renders live. Defaults to {TempPath}/blizzard.</summary>
        public string CacheDirectory { get; set; } = "";
        /// <summary>
        /// Opaque backdrop the trimmed render is flattened onto before it reaches the image model.
        /// Neutral gray by default: a saturated colour (e.g. the class colour) injects a large
        /// palette cue that the model tends to echo back into armour and lighting.
        /// </summary>
        public string ReferenceBackground { get; set; } = "#808080";
        /// <summary>Padding added around the trimmed subject, as a fraction of its size.</summary>
        public double PaddingFraction { get; set; } = 0.08;
        /// <summary>Alpha value a pixel must exceed to count as part of the subject.</summary>
        public int AlphaThreshold { get; set; } = 8;
        /// <summary>Realm name -> slug overrides, for realms the index does not resolve.</summary>
        public Dictionary<string, string> RealmSlugOverrides { get; set; } = new();
    }

    public static AppConfig Load(CliOptions options, RunLogger logger)
    {
        var configPath = options.ConfigPath;
        if (string.IsNullOrWhiteSpace(configPath))
        {
            configPath = Path.Combine(AppContext.BaseDirectory, "appsettings.json");
        }
        else
        {
            configPath = Path.GetFullPath(configPath);
        }

        AppConfig cfg;
        if (File.Exists(configPath))
        {
            var json = File.ReadAllText(configPath);
            cfg = JsonSerializer.Deserialize<AppConfig>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            }) ?? new AppConfig();
            logger.Info($"Config file: {configPath}");
        }
        else
        {
            logger.Warn($"Config file not found: {configPath}. Using defaults + CLI overrides.");
            cfg = new AppConfig();
        }

        if (!string.IsNullOrWhiteSpace(options.InputPath)) cfg.InputDataPath = options.InputPath;
        if (!string.IsNullOrWhiteSpace(options.OutputDirectory)) cfg.OutputRenderDirectory = options.OutputDirectory;
        if (!string.IsNullOrWhiteSpace(options.AddonMediaDirectory)) cfg.AddonMediaDirectory = options.AddonMediaDirectory;
        if (!string.IsNullOrWhiteSpace(options.ManifestPath)) cfg.ManifestOutputPath = options.ManifestPath;
        if (!string.IsNullOrWhiteSpace(options.StagingDirectory)) cfg.RenderStagingPath = options.StagingDirectory;
        if (!string.IsNullOrWhiteSpace(options.TempDirectory)) cfg.TempPath = options.TempDirectory;
        if (!string.IsNullOrWhiteSpace(options.ConverterPath)) cfg.ConverterExecutable = options.ConverterPath;
        if (!string.IsNullOrWhiteSpace(options.RenderBackend)) cfg.RenderBackend = options.RenderBackend;
        if (options.MaxAgeDaysOverride.HasValue) cfg.MaxAgeDays = options.MaxAgeDaysOverride.Value;

        cfg.InputDataPath = Path.GetFullPath(cfg.InputDataPath);
        cfg.OutputRenderDirectory = Path.GetFullPath(cfg.OutputRenderDirectory);
        cfg.AddonMediaDirectory = Path.GetFullPath(cfg.AddonMediaDirectory);
        cfg.ManifestOutputPath = Path.GetFullPath(cfg.ManifestOutputPath);
        cfg.RenderStagingPath = Path.GetFullPath(cfg.RenderStagingPath);
        cfg.TempPath = Path.GetFullPath(cfg.TempPath);
        cfg.WowAddonImageRoot = PathTools.NormalizeWowPath(cfg.WowAddonImageRoot);
        cfg.RenderBackend = NormalizeRenderBackend(cfg.RenderBackend);

        if (cfg.RenderSpec.Width <= 0) cfg.RenderSpec.Width = 512;
        if (cfg.RenderSpec.Height <= 0) cfg.RenderSpec.Height = 512;
        cfg.RenderSpec.BackgroundColorFallback = string.IsNullOrWhiteSpace(cfg.RenderSpec.BackgroundColorFallback)
            ? "#141414"
            : cfg.RenderSpec.BackgroundColorFallback.Trim();
        cfg.RenderSpec.FramingPreset = string.IsNullOrWhiteSpace(cfg.RenderSpec.FramingPreset)
            ? "fullbody_center_v1"
            : cfg.RenderSpec.FramingPreset.Trim();
        cfg.RenderSpec.PreferredStagingExtension = PathTools.NormalizeExtension(
            cfg.RenderSpec.PreferredStagingExtension,
            ".png");

        if (!PathTools.IsValidWowAddonImagePath(PathTools.CombineWowPath(cfg.WowAddonImageRoot, "probe.tga")))
        {
            throw new PipelineDataException(
                $"Invalid WowAddonImageRoot: {cfg.WowAddonImageRoot}. Expected a relative addon path like Interface\\AddOns\\AltTracker\\Media\\CharacterRenders");
        }

        cfg.HeroShot.Style = string.IsNullOrWhiteSpace(cfg.HeroShot.Style) ? "realistic" : cfg.HeroShot.Style.Trim().ToLowerInvariant();
        if (cfg.HeroShot.Style is not ("realistic" or "wow-like" or "cartoonish"))
            throw new PipelineDataException($"Invalid HeroShot.Style: {cfg.HeroShot.Style}. Allowed: realistic, wow-like, cartoonish.");
        cfg.HeroShot.Width = Math.Max(64, cfg.HeroShot.Width);
        cfg.HeroShot.Height = Math.Max(64, cfg.HeroShot.Height);
        cfg.HeroShot.Provider = string.IsNullOrWhiteSpace(cfg.HeroShot.Provider) ? "codex" : cfg.HeroShot.Provider.Trim().ToLowerInvariant();
        cfg.HeroShot.Model = string.IsNullOrWhiteSpace(cfg.HeroShot.Model) ? "gpt-image-1" : cfg.HeroShot.Model.Trim();
        cfg.HeroShot.PromptTemplateVersion = string.IsNullOrWhiteSpace(cfg.HeroShot.PromptTemplateVersion) ? "v2" : cfg.HeroShot.PromptTemplateVersion.Trim();
        cfg.HeroShot.GenerationVersion = string.IsNullOrWhiteSpace(cfg.HeroShot.GenerationVersion) ? "1" : cfg.HeroShot.GenerationVersion.Trim();
        cfg.HeroShot.TimeoutSeconds = Math.Max(30, cfg.HeroShot.TimeoutSeconds);
        cfg.HeroShot.OutputFormat = string.IsNullOrWhiteSpace(cfg.HeroShot.OutputFormat) ? "png" : cfg.HeroShot.OutputFormat.Trim().ToLowerInvariant();
        cfg.HeroShot.OutputWidth = Math.Max(64, cfg.HeroShot.OutputWidth);
        cfg.HeroShot.OutputHeight = Math.Max(64, cfg.HeroShot.OutputHeight);
        cfg.HeroShot.CropMode = string.IsNullOrWhiteSpace(cfg.HeroShot.CropMode) ? "cover" : cfg.HeroShot.CropMode.Trim().ToLowerInvariant();
        if (cfg.HeroShot.CropMode != "cover")
            throw new PipelineDataException($"Invalid HeroShot.CropMode: {cfg.HeroShot.CropMode}. Allowed: cover.");
        cfg.HeroShot.Anchor = string.IsNullOrWhiteSpace(cfg.HeroShot.Anchor) ? "center" : cfg.HeroShot.Anchor.Trim().ToLowerInvariant();
        if (cfg.HeroShot.Anchor != "center")
            throw new PipelineDataException($"Invalid HeroShot.Anchor: {cfg.HeroShot.Anchor}. Allowed: center.");
        cfg.HeroShot.Format = string.IsNullOrWhiteSpace(cfg.HeroShot.Format) ? "tga" : cfg.HeroShot.Format.Trim().ToLowerInvariant();
        if (cfg.HeroShot.Format != "tga")
            throw new PipelineDataException($"Invalid HeroShot.Format: {cfg.HeroShot.Format}. Allowed: tga.");
        if (!string.IsNullOrWhiteSpace(cfg.HeroShot.ReferenceImagesPath))
            cfg.HeroShot.ReferenceImagesPath = Path.GetFullPath(cfg.HeroShot.ReferenceImagesPath);
        cfg.HeroShot.CharacterReferenceImages ??= new Dictionary<string, string>();
        foreach (var key in cfg.HeroShot.CharacterReferenceImages.Keys.ToList())
        {
            var val = cfg.HeroShot.CharacterReferenceImages[key];
            if (!string.IsNullOrWhiteSpace(val))
                cfg.HeroShot.CharacterReferenceImages[key] = Path.GetFullPath(val);
        }

        if (!string.IsNullOrWhiteSpace(options.HeroShotStyle)) cfg.HeroShot.Style = options.HeroShotStyle;

        // HeroShot output policy defines the final addon texture dimensions used by conversion/publish.
        if (cfg.RenderBackend.Equals("HeroShot", StringComparison.OrdinalIgnoreCase))
        {
            cfg.RenderSpec.Width = cfg.HeroShot.OutputWidth;
            cfg.RenderSpec.Height = cfg.HeroShot.OutputHeight;
            cfg.RenderSpec.PreferredStagingExtension = ".png";
        }

        cfg.HeroShot.Codex.CodexExecutable = string.IsNullOrWhiteSpace(cfg.HeroShot.Codex.CodexExecutable)
            ? "codex" : cfg.HeroShot.Codex.CodexExecutable.Trim();
        cfg.HeroShot.Codex.ReasoningEffort = string.IsNullOrWhiteSpace(cfg.HeroShot.Codex.ReasoningEffort)
            ? "low" : cfg.HeroShot.Codex.ReasoningEffort.Trim().ToLowerInvariant();
        if (cfg.HeroShot.Codex.ReasoningEffort is not ("low" or "medium" or "high"))
            throw new PipelineDataException($"Invalid HeroShot.Codex.ReasoningEffort: {cfg.HeroShot.Codex.ReasoningEffort}. Allowed: low, medium, high.");
        cfg.HeroShot.Codex.TimeoutSeconds = Math.Max(30, cfg.HeroShot.Codex.TimeoutSeconds);
        cfg.HeroShot.Codex.ExtraArgs = (cfg.HeroShot.Codex.ExtraArgs ?? "").Trim();

        return cfg;
    }

    private static string NormalizeRenderBackend(string value)
    {
        var token = (value ?? "").Trim();
        if (token.Equals("HeroShot", StringComparison.OrdinalIgnoreCase)) return "HeroShot";
        throw new PipelineDataException($"Invalid RenderBackend: {value}. Allowed: HeroShot.");
    }
}
