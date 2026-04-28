using System.Text.Json;
using AltTracker.RenderPipeline.Services;

namespace AltTracker.RenderPipeline.Infrastructure;

public sealed class AppConfig
{
    public string InputDataPath { get; set; } = @"C:\Path\To\AltTracker.lua";
    public string OutputRenderDirectory { get; set; } = @"C:\Path\To\AltTracker\Media\CharacterRenders";
    public string AddonMediaDirectory { get; set; } = @"C:\Path\To\AltTracker\Media\CharacterRenders";
    public string ManifestOutputPath { get; set; } = @"C:\Path\To\AltTrackerRenderManifest.lua";
    public string WmvxExePath { get; set; } = @"C:\Path\To\wmvx.exe";
    public string RenderStagingPath { get; set; } = @"C:\Path\To\RenderStaging";
    public string TempPath { get; set; } = @"C:\Path\To\AltTrackerRenderTemp";
    public string ConverterExecutable { get; set; } = "magick";
    public string WowAddonImageRoot { get; set; } = @"Interface\AddOns\AltTracker\Media\CharacterRenders";
    public int MaxAgeDays { get; set; } = 30;
    public string RenderBackend { get; set; } = "ManualWmvx";
    public string RenderMode { get; set; } = "fullbody";
    public string RenderProfileVersion { get; set; } = "v1";
    public string Resolution { get; set; } = "512x512";
    public RenderSpecConfig RenderSpec { get; set; } = new();
    public WmvxPolicyConfig WmvxPolicy { get; set; } = new();
    public WowConverterConfig WowConverter { get; set; } = new();
    public HeroShotConfig HeroShot { get; set; } = new();

    public sealed class RenderSpecConfig
    {
        public int Width { get; set; } = 512;
        public int Height { get; set; } = 512;
        public bool PreferTransparentBackground { get; set; } = true;
        public string BackgroundColorFallback { get; set; } = "#141414";
        public string FramingPreset { get; set; } = "fullbody_center_v1";
        public string PreferredStagingExtension { get; set; } = ".png";
    }

    public sealed class WmvxPolicyConfig
    {
        public string PreferredClientProfile { get; set; } = "Retail";
        public string FallbackClientProfile { get; set; } = "Midnight";
        public bool AllowAnyWorkingClientProfile { get; set; } = true;
        public string MissingItemPolicy { get; set; } = "skip";
        public string PlaceholderLabel { get; set; } = "missing-item";
    }

    public sealed class WowConverterConfig
    {
        public string WowExportUrl { get; set; } = "http://127.0.0.1:17752";
        public string ConverterUrl { get; set; } = "http://127.0.0.1:3001";
        public string ExpectedWowExportProduct { get; set; } = "";
        public string ExpectedWowExportVersionContains { get; set; } = "";
        public bool RequireExpectedWowExportProduct { get; set; } = false;
        public string WowExportExecutablePath { get; set; } = "";
        public string ConverterExecutablePath { get; set; } = "";
        public string ExportedAssetsPath { get; set; } = @"C:\Temp\wow-converter\exported-assets";
        public string NodeExecutable { get; set; } = "node";
        public string NpmExecutable { get; set; } = "npm.cmd";
        public string NpxExecutable { get; set; } = "npx.cmd";
        public string PlaywrightScriptPath { get; set; } = "";
        public int ScreenshotWidth { get; set; } = 1400;
        public int ScreenshotHeight { get; set; } = 1000;
        public int ViewerWaitTimeoutSeconds { get; set; } = 45;
        public int ExportTimeoutSeconds { get; set; } = 120;
        public int PollIntervalMilliseconds { get; set; } = 100;
        public string CaptureTarget { get; set; } = "canvas";
        public bool IncludeTextures { get; set; } = true;
        public bool RemoveUnusedMaterialsTextures { get; set; } = true;
        public bool PreferTransparentBackground { get; set; } = true;
        public string BackgroundColorFallback { get; set; } = "#141414";
        public bool DryRunValidateEndpoints { get; set; } = true;
        public string GlobalInputFallback { get; set; } = "";
        public Dictionary<string, string> InputOverrides { get; set; } = new();
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
        public string Provider { get; set; } = "openai";
        public string Model { get; set; } = "gpt-image-1";
        public string PromptTemplateVersion { get; set; } = "v2";
        public string GenerationVersion { get; set; } = "1";
        public string ApiBaseUrl { get; set; } = "https://api.openai.com/v1";
        public string ApiKeyEnvVar { get; set; } = "ALTRACKER_HEROSHOT_API_KEY";
        public string ReferenceImagesPath { get; set; } = "";
        public int TimeoutSeconds { get; set; } = 120;
        public int MaxRetries { get; set; } = 2;
        public Dictionary<string, string> CharacterReferenceImages { get; set; } = new();
        /// <summary>
        /// When true, characters without a resolved reference image are skipped rather than
        /// generating a text-only portrait. Recommended for browser-based providers where
        /// a reference image is essential for identity accuracy.
        /// </summary>
        public bool RequireReferenceImage { get; set; } = false;
        public BrowserChatGptConfig BrowserChatGpt { get; set; } = new();

        public sealed class BrowserChatGptConfig
        {
            /// <summary>
            /// Directory for the persistent Chrome profile used by generate.mjs.
            /// Run save-auth.mjs once to create and populate this profile.
            /// </summary>
            public string ChromeProfilePath { get; set; } = "";
            /// <summary>
            /// Fallback: path to a Playwright storage-state JSON if no ChromeProfilePath is set.
            /// </summary>
            public string AuthStatePath { get; set; } = "";
            /// <summary>Path to Tools/heroshot-chatgpt/generate.mjs.</summary>
            public string GenerateScriptPath { get; set; } = "";
            /// <summary>
            /// JSON file storing character key → ChatGPT conversation URL mappings so
            /// subsequent runs resume the same conversation for context continuity.
            /// Defaults to conversations.json in the same parent directory as ChromeProfilePath.
            /// </summary>
            public string ConversationsFilePath { get; set; } = "";
            public string NodeExecutable { get; set; } = "node";
            public bool Headless { get; set; } = false;
            public int TimeoutSeconds { get; set; } = 180;
        }
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
        if (!string.IsNullOrWhiteSpace(options.WmvxPath)) cfg.WmvxExePath = options.WmvxPath;
        if (!string.IsNullOrWhiteSpace(options.StagingDirectory)) cfg.RenderStagingPath = options.StagingDirectory;
        if (!string.IsNullOrWhiteSpace(options.TempDirectory)) cfg.TempPath = options.TempDirectory;
        if (!string.IsNullOrWhiteSpace(options.ConverterPath)) cfg.ConverterExecutable = options.ConverterPath;
        if (!string.IsNullOrWhiteSpace(options.RenderBackend)) cfg.RenderBackend = options.RenderBackend;
        if (!string.IsNullOrWhiteSpace(options.ConverterUrl)) cfg.WowConverter.ConverterUrl = options.ConverterUrl;
        if (!string.IsNullOrWhiteSpace(options.WowExportUrl)) cfg.WowConverter.WowExportUrl = options.WowExportUrl;
        if (!string.IsNullOrWhiteSpace(options.ExportedAssetsPath)) cfg.WowConverter.ExportedAssetsPath = options.ExportedAssetsPath;
        if (!string.IsNullOrWhiteSpace(options.NodePath)) cfg.WowConverter.NodeExecutable = options.NodePath;
        if (!string.IsNullOrWhiteSpace(options.NpmPath)) cfg.WowConverter.NpmExecutable = options.NpmPath;
        if (!string.IsNullOrWhiteSpace(options.NpxPath)) cfg.WowConverter.NpxExecutable = options.NpxPath;
        if (!string.IsNullOrWhiteSpace(options.PlaywrightScriptPath)) cfg.WowConverter.PlaywrightScriptPath = options.PlaywrightScriptPath;
        if (!string.IsNullOrWhiteSpace(options.CaptureTarget)) cfg.WowConverter.CaptureTarget = options.CaptureTarget;
        if (!string.IsNullOrWhiteSpace(options.ConverterInputFallback)) cfg.WowConverter.GlobalInputFallback = options.ConverterInputFallback;
        if (options.ExportTimeoutSeconds.HasValue) cfg.WowConverter.ExportTimeoutSeconds = options.ExportTimeoutSeconds.Value;
        if (options.ViewerTimeoutSeconds.HasValue) cfg.WowConverter.ViewerWaitTimeoutSeconds = options.ViewerTimeoutSeconds.Value;
        if (options.ScreenshotWidth.HasValue) cfg.WowConverter.ScreenshotWidth = options.ScreenshotWidth.Value;
        if (options.ScreenshotHeight.HasValue) cfg.WowConverter.ScreenshotHeight = options.ScreenshotHeight.Value;
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
        cfg.WmvxPolicy.PreferredClientProfile = string.IsNullOrWhiteSpace(cfg.WmvxPolicy.PreferredClientProfile)
            ? "Retail"
            : cfg.WmvxPolicy.PreferredClientProfile.Trim();
        cfg.WmvxPolicy.FallbackClientProfile = string.IsNullOrWhiteSpace(cfg.WmvxPolicy.FallbackClientProfile)
            ? "Midnight"
            : cfg.WmvxPolicy.FallbackClientProfile.Trim();
        cfg.WmvxPolicy.MissingItemPolicy = string.IsNullOrWhiteSpace(cfg.WmvxPolicy.MissingItemPolicy)
            ? "skip"
            : cfg.WmvxPolicy.MissingItemPolicy.Trim().ToLowerInvariant();
        if (cfg.WmvxPolicy.MissingItemPolicy is not ("skip" or "placeholder"))
        {
            throw new PipelineDataException(
                $"Invalid WmvxPolicy.MissingItemPolicy: {cfg.WmvxPolicy.MissingItemPolicy}. Allowed: skip, placeholder.");
        }
        cfg.WmvxPolicy.PlaceholderLabel = string.IsNullOrWhiteSpace(cfg.WmvxPolicy.PlaceholderLabel)
            ? "missing-item"
            : cfg.WmvxPolicy.PlaceholderLabel.Trim();

        cfg.WowConverter.WowExportUrl = NormalizeUrl(cfg.WowConverter.WowExportUrl, "http://127.0.0.1:17752");
        cfg.WowConverter.ConverterUrl = NormalizeUrl(cfg.WowConverter.ConverterUrl, "http://127.0.0.1:3001");
        cfg.WowConverter.ExpectedWowExportProduct = cfg.WowConverter.ExpectedWowExportProduct?.Trim() ?? "";
        cfg.WowConverter.ExpectedWowExportVersionContains = cfg.WowConverter.ExpectedWowExportVersionContains?.Trim() ?? "";
        cfg.WowConverter.WowExportExecutablePath = string.IsNullOrWhiteSpace(cfg.WowConverter.WowExportExecutablePath)
            ? ""
            : Path.GetFullPath(cfg.WowConverter.WowExportExecutablePath.Trim());
        cfg.WowConverter.ConverterExecutablePath = string.IsNullOrWhiteSpace(cfg.WowConverter.ConverterExecutablePath)
            ? ""
            : Path.GetFullPath(cfg.WowConverter.ConverterExecutablePath.Trim());
        cfg.WowConverter.ExportedAssetsPath = string.IsNullOrWhiteSpace(cfg.WowConverter.ExportedAssetsPath)
            ? cfg.RenderStagingPath
            : Path.GetFullPath(cfg.WowConverter.ExportedAssetsPath);
        cfg.WowConverter.NodeExecutable = string.IsNullOrWhiteSpace(cfg.WowConverter.NodeExecutable) ? "node" : cfg.WowConverter.NodeExecutable.Trim();
        cfg.WowConverter.NpmExecutable = string.IsNullOrWhiteSpace(cfg.WowConverter.NpmExecutable) ? "npm.cmd" : cfg.WowConverter.NpmExecutable.Trim();
        cfg.WowConverter.NpxExecutable = string.IsNullOrWhiteSpace(cfg.WowConverter.NpxExecutable) ? "npx.cmd" : cfg.WowConverter.NpxExecutable.Trim();
        if (!string.IsNullOrWhiteSpace(cfg.WowConverter.PlaywrightScriptPath))
        {
            cfg.WowConverter.PlaywrightScriptPath = Path.GetFullPath(cfg.WowConverter.PlaywrightScriptPath);
        }
        cfg.WowConverter.CaptureTarget = NormalizeCaptureTarget(cfg.WowConverter.CaptureTarget);
        cfg.WowConverter.BackgroundColorFallback = string.IsNullOrWhiteSpace(cfg.WowConverter.BackgroundColorFallback)
            ? "#141414"
            : cfg.WowConverter.BackgroundColorFallback.Trim();
        cfg.WowConverter.ScreenshotWidth = Math.Max(1, cfg.WowConverter.ScreenshotWidth);
        cfg.WowConverter.ScreenshotHeight = Math.Max(1, cfg.WowConverter.ScreenshotHeight);
        cfg.WowConverter.ViewerWaitTimeoutSeconds = Math.Max(1, cfg.WowConverter.ViewerWaitTimeoutSeconds);
        cfg.WowConverter.ExportTimeoutSeconds = Math.Max(1, cfg.WowConverter.ExportTimeoutSeconds);
        cfg.WowConverter.PollIntervalMilliseconds = Math.Max(100, cfg.WowConverter.PollIntervalMilliseconds);
        cfg.WowConverter.GlobalInputFallback = cfg.WowConverter.GlobalInputFallback?.Trim() ?? "";
        if (cfg.WowConverter.InputOverrides is null)
        {
            cfg.WowConverter.InputOverrides = new Dictionary<string, string>();
        }

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
        cfg.HeroShot.Provider = string.IsNullOrWhiteSpace(cfg.HeroShot.Provider) ? "openai" : cfg.HeroShot.Provider.Trim().ToLowerInvariant();
        cfg.HeroShot.Model = string.IsNullOrWhiteSpace(cfg.HeroShot.Model) ? "gpt-image-1" : cfg.HeroShot.Model.Trim();
        cfg.HeroShot.PromptTemplateVersion = string.IsNullOrWhiteSpace(cfg.HeroShot.PromptTemplateVersion) ? "v2" : cfg.HeroShot.PromptTemplateVersion.Trim();
        cfg.HeroShot.GenerationVersion = string.IsNullOrWhiteSpace(cfg.HeroShot.GenerationVersion) ? "1" : cfg.HeroShot.GenerationVersion.Trim();
        cfg.HeroShot.ApiBaseUrl = string.IsNullOrWhiteSpace(cfg.HeroShot.ApiBaseUrl) ? "https://api.openai.com/v1" : cfg.HeroShot.ApiBaseUrl.TrimEnd('/');
        cfg.HeroShot.ApiKeyEnvVar = string.IsNullOrWhiteSpace(cfg.HeroShot.ApiKeyEnvVar) ? "ALTRACKER_HEROSHOT_API_KEY" : cfg.HeroShot.ApiKeyEnvVar.Trim();
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

        cfg.HeroShot.BrowserChatGpt.NodeExecutable = string.IsNullOrWhiteSpace(cfg.HeroShot.BrowserChatGpt.NodeExecutable)
            ? "node" : cfg.HeroShot.BrowserChatGpt.NodeExecutable.Trim();
        cfg.HeroShot.BrowserChatGpt.TimeoutSeconds = Math.Max(30, cfg.HeroShot.BrowserChatGpt.TimeoutSeconds);
        if (!string.IsNullOrWhiteSpace(cfg.HeroShot.BrowserChatGpt.GenerateScriptPath))
            cfg.HeroShot.BrowserChatGpt.GenerateScriptPath = Path.GetFullPath(cfg.HeroShot.BrowserChatGpt.GenerateScriptPath);
        if (!string.IsNullOrWhiteSpace(cfg.HeroShot.BrowserChatGpt.AuthStatePath))
            cfg.HeroShot.BrowserChatGpt.AuthStatePath = Path.GetFullPath(cfg.HeroShot.BrowserChatGpt.AuthStatePath);
        if (!string.IsNullOrWhiteSpace(cfg.HeroShot.BrowserChatGpt.ChromeProfilePath))
            cfg.HeroShot.BrowserChatGpt.ChromeProfilePath = Path.GetFullPath(cfg.HeroShot.BrowserChatGpt.ChromeProfilePath);

        // Default ConversationsFilePath to conversations.json next to the profile dir
        if (string.IsNullOrWhiteSpace(cfg.HeroShot.BrowserChatGpt.ConversationsFilePath)
            && !string.IsNullOrWhiteSpace(cfg.HeroShot.BrowserChatGpt.ChromeProfilePath))
        {
            cfg.HeroShot.BrowserChatGpt.ConversationsFilePath = Path.Combine(
                Path.GetDirectoryName(cfg.HeroShot.BrowserChatGpt.ChromeProfilePath)!,
                "conversations.json");
        }
        else if (!string.IsNullOrWhiteSpace(cfg.HeroShot.BrowserChatGpt.ConversationsFilePath))
        {
            cfg.HeroShot.BrowserChatGpt.ConversationsFilePath =
                Path.GetFullPath(cfg.HeroShot.BrowserChatGpt.ConversationsFilePath);
        }

        return cfg;
    }

    private static string NormalizeRenderBackend(string value)
    {
        var token = (value ?? "").Trim();
        if (token.Equals("ManualWmvx", StringComparison.OrdinalIgnoreCase)) return "ManualWmvx";
        if (token.Equals("WowConverter", StringComparison.OrdinalIgnoreCase)) return "WowConverter";
        if (token.Equals("HeroShot", StringComparison.OrdinalIgnoreCase)) return "HeroShot";
        throw new PipelineDataException($"Invalid RenderBackend: {value}. Allowed: ManualWmvx, WowConverter, HeroShot.");
    }

    private static string NormalizeCaptureTarget(string value)
    {
        var token = (value ?? "").Trim();
        if (token.Equals("canvas", StringComparison.OrdinalIgnoreCase)) return "canvas";
        if (token.Equals("full", StringComparison.OrdinalIgnoreCase) || token.Equals("viewer", StringComparison.OrdinalIgnoreCase)) return "full";
        throw new PipelineDataException($"Invalid WowConverter.CaptureTarget: {value}. Allowed: canvas, full.");
    }

    private static string NormalizeUrl(string value, string fallback)
    {
        var raw = string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();
        raw = raw.TrimEnd('/');
        if (!Uri.TryCreate(raw, UriKind.Absolute, out var uri) || (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps))
        {
            throw new PipelineDataException($"Invalid URL: {raw}");
        }
        return raw;
    }
}
