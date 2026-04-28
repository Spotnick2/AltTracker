using System.Diagnostics;
using System.Text;
using System.Text.Json;
using AltTracker.RenderPipeline.Infrastructure;

namespace AltTracker.RenderPipeline.Services.HeroShot;

/// <summary>
/// Generates hero shots by automating ChatGPT's web interface via a Node.js Playwright script.
/// Requires a saved auth state (run Tools/heroshot-chatgpt/save-auth.mjs once).
/// </summary>
public sealed class BrowserChatGptProvider : IHeroShotRenderProvider
{
    private readonly AppConfig.HeroShotConfig _cfg;
    private readonly RunLogger _logger;

    public string ProviderId => "browserchatgpt";

    public BrowserChatGptProvider(AppConfig.HeroShotConfig cfg, RunLogger logger)
    {
        _cfg = cfg;
        _logger = logger;

        var scriptPath = cfg.BrowserChatGpt.GenerateScriptPath;
        if (string.IsNullOrWhiteSpace(scriptPath) || !File.Exists(scriptPath))
        {
            throw new PipelineDataException(
                $"HeroShot BrowserChatGpt: generate script not found at '{scriptPath}'. " +
                $"Set HeroShot.BrowserChatGpt.GenerateScriptPath to the full path of " +
                $"Tools\\heroshot-chatgpt\\generate.mjs in appsettings.json.");
        }
    }

    public async Task<HeroShotResponse> GenerateAsync(HeroShotRequest request, CancellationToken cancellationToken = default)
    {
        var chatGptCfg = _cfg.BrowserChatGpt;
        var outputPath = Path.Combine(Path.GetTempPath(), $"heroshot-out-{Guid.NewGuid():N}.png");
        var convOutPath = Path.Combine(Path.GetTempPath(), $"heroshot-conv-{Guid.NewGuid():N}.txt");
        string? refTempPath = null;

        try
        {
            // Write reference bytes to a temp file for the script
            if (request.ReferenceImageBytes is { Length: > 0 })
            {
                refTempPath = Path.Combine(Path.GetTempPath(), $"heroshot-ref-{Guid.NewGuid():N}.png");
                await File.WriteAllBytesAsync(refTempPath, request.ReferenceImageBytes, cancellationToken);
                _logger.Info($"[ChatGPT] Reference image temp: {refTempPath} ({request.ReferenceImageBytes.Length} bytes)");
            }

            // Look up existing conversation URL for this character
            var existingConvUrl = LoadConversationUrl(chatGptCfg, request.IdempotencyKey);
            if (existingConvUrl is not null)
                _logger.Info($"[ChatGPT] Resuming conversation for {request.IdempotencyKey}: {existingConvUrl}");

            var args = BuildArguments(chatGptCfg, request.Prompt, outputPath, refTempPath, existingConvUrl, convOutPath);
            var nodeExe = string.IsNullOrWhiteSpace(chatGptCfg.NodeExecutable) ? "node" : chatGptCfg.NodeExecutable;

            _logger.Info($"[ChatGPT] Running: {nodeExe} {args[..Math.Min(120, args.Length)]}...");
            if (!chatGptCfg.Headless)
                _logger.Info("[ChatGPT] Browser will open visually. You may need to interact if the session has expired.");

            using var process = new Process
            {
                StartInfo = new ProcessStartInfo(nodeExe, args)
                {
                    RedirectStandardOutput = true,
                    RedirectStandardError  = true,
                    UseShellExecute        = false,
                    CreateNoWindow         = true,
                },
            };

            var stdout = new StringBuilder();
            var stderr = new StringBuilder();
            process.OutputDataReceived += (_, e) =>
            {
                if (e.Data is not null)
                {
                    stdout.AppendLine(e.Data);
                    _logger.Info($"[ChatGPT] {e.Data}");
                }
            };
            process.ErrorDataReceived += (_, e) =>
            {
                if (e.Data is not null)
                {
                    stderr.AppendLine(e.Data);
                    _logger.Warn($"[ChatGPT] STDERR: {e.Data}");
                }
            };

            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            // Give the script extra buffer beyond its own timeout
            var totalMs = (chatGptCfg.TimeoutSeconds + 60) * 1000;
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            cts.CancelAfter(totalMs);

            await process.WaitForExitAsync(cts.Token);

            if (process.ExitCode != 0)
            {
                var detail = (stderr.Length > 0 ? stderr : stdout).ToString();
                return new HeroShotResponse
                {
                    Success = false,
                    Error = $"chatgpt-generate exited {process.ExitCode}: {detail[..Math.Min(400, detail.Length)].Trim()}"
                };
            }

            if (!File.Exists(outputPath) || new FileInfo(outputPath).Length < 100)
            {
                return new HeroShotResponse
                {
                    Success = false,
                    Error = "chatgpt-generate succeeded but output file is missing or empty"
                };
            }

            // Persist the conversation URL so the next run resumes context
            if (File.Exists(convOutPath))
            {
                var newConvUrl = (await File.ReadAllTextAsync(convOutPath, cancellationToken)).Trim();
                if (!string.IsNullOrWhiteSpace(newConvUrl))
                {
                    SaveConversationUrl(chatGptCfg, request.IdempotencyKey, newConvUrl);
                    _logger.Info($"[ChatGPT] Conversation stored for {request.IdempotencyKey}: {newConvUrl}");
                }
            }

            var imageBytes = await File.ReadAllBytesAsync(outputPath, cancellationToken);
            _logger.Info($"[ChatGPT] Image ready: {imageBytes.Length} bytes");

            return new HeroShotResponse { Success = true, ImageBytes = imageBytes };
        }
        catch (OperationCanceledException)
        {
            return new HeroShotResponse { Success = false, Error = "ChatGPT browser generation timed out." };
        }
        catch (Exception ex)
        {
            return new HeroShotResponse { Success = false, Error = $"ChatGPT browser generation failed: {ex.Message}" };
        }
        finally
        {
            if (File.Exists(outputPath))
                try { File.Delete(outputPath); } catch { /* best effort */ }
            if (refTempPath is not null && File.Exists(refTempPath))
                try { File.Delete(refTempPath); } catch { /* best effort */ }
            if (File.Exists(convOutPath))
                try { File.Delete(convOutPath); } catch { /* best effort */ }
        }
    }

    // ── Conversation store ────────────────────────────────────────────────────

    private static string? LoadConversationUrl(AppConfig.HeroShotConfig.BrowserChatGptConfig cfg, string key)
    {
        var path = cfg.ConversationsFilePath;
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return null;
        try
        {
            var dict = JsonSerializer.Deserialize<Dictionary<string, string>>(
                File.ReadAllText(path),
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            return dict?.GetValueOrDefault(key.ToLowerInvariant());
        }
        catch { return null; }
    }

    private static void SaveConversationUrl(AppConfig.HeroShotConfig.BrowserChatGptConfig cfg, string key, string url)
    {
        var path = cfg.ConversationsFilePath;
        if (string.IsNullOrWhiteSpace(path)) return;
        try
        {
            Dictionary<string, string> dict = new();
            if (File.Exists(path))
            {
                dict = JsonSerializer.Deserialize<Dictionary<string, string>>(
                    File.ReadAllText(path),
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new();
            }
            dict[key.ToLowerInvariant()] = url;
            var dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrWhiteSpace(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(path, JsonSerializer.Serialize(dict, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { /* best effort — don't fail a generation over conversation persistence */ }
    }

    // ── Argument builder ──────────────────────────────────────────────────────

    private static string BuildArguments(
        AppConfig.HeroShotConfig.BrowserChatGptConfig cfg,
        string prompt,
        string outputPath,
        string? refTempPath,
        string? conversationUrl,
        string? convOutPath)
    {
        var sb = new StringBuilder();
        sb.Append(Q(cfg.GenerateScriptPath));
        sb.Append(" --prompt ").Append(Q(prompt));
        sb.Append(" --output ").Append(Q(outputPath));
        sb.Append(" --timeout ").Append(cfg.TimeoutSeconds);

        // Prefer persistent Chrome profile; fall back to auth-state JSON
        if (!string.IsNullOrWhiteSpace(cfg.ChromeProfilePath))
            sb.Append(" --profile-path ").Append(Q(cfg.ChromeProfilePath));
        else if (!string.IsNullOrWhiteSpace(cfg.AuthStatePath))
            sb.Append(" --auth-state ").Append(Q(cfg.AuthStatePath));

        if (!string.IsNullOrWhiteSpace(refTempPath))
            sb.Append(" --reference ").Append(Q(refTempPath));

        if (!string.IsNullOrWhiteSpace(conversationUrl))
            sb.Append(" --conversation-url ").Append(Q(conversationUrl));

        if (!string.IsNullOrWhiteSpace(convOutPath))
            sb.Append(" --conversation-out ").Append(Q(convOutPath));

        if (cfg.Headless)
            sb.Append(" --headless");

        return sb.ToString();
    }

    private static string Q(string value) => $"\"{value.Replace("\"", "\\\"")}\"";
}


