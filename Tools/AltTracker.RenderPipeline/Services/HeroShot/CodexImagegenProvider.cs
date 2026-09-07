using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using AltTracker.RenderPipeline.Infrastructure;

namespace AltTracker.RenderPipeline.Services.HeroShot;

/// <summary>
/// Generates hero shots by driving the OpenAI <c>codex</c> CLI's built-in <c>image_gen</c> tool
/// headlessly (<c>codex exec</c>). Uses codex's ChatGPT-login auth — no OpenAI API key required.
///
/// The reference image (bytes already in memory) is written to a temp file and loaded by codex via
/// <c>view_image</c>; codex saves the generated PNG under its own <c>generated_images</c> directory,
/// which this provider then harvests with <b>fail-closed attribution</b> (exactly one new file, or
/// fail — never "newest wins", which would silently produce the wrong portrait).
///
/// Gotchas reproduced from <c>.claude/skills/codex-consult</c>: prompt goes via stdin (closed for
/// EOF, else codex hangs), the answer is read from the <c>-o</c> file (stdout is progress noise),
/// <c>--ephemeral</c> avoids session-log bloat, and only the exact process tree we started is killed.
/// </summary>
public sealed class CodexImagegenProvider : IHeroShotRenderProvider
{
    private static readonly byte[] PngMagic = { 0x89, 0x50, 0x4E, 0x47 };

    /// <summary>Ratio slack before a frame counts as "too tall". Rounding to whole pixels moves the ratio
    /// slightly, so an exact-size render must not trip the warning.</summary>
    private const double AspectTolerance = 0.005;

    private readonly AppConfig.HeroShotConfig _cfg;
    private readonly RunLogger _logger;

    public string ProviderId => "codex";

    public CodexImagegenProvider(AppConfig.HeroShotConfig cfg, RunLogger logger)
    {
        _cfg = cfg;
        _logger = logger;
    }

    public Task<HeroShotResponse> GenerateAsync(HeroShotRequest request, CancellationToken cancellationToken = default)
        => Task.FromResult(Generate(request));

    private HeroShotResponse Generate(HeroShotRequest request)
    {
        var codexCfg = _cfg.Codex;
        var verdictPath = Path.Combine(Path.GetTempPath(), $"heroshot-codex-verdict-{Guid.NewGuid():N}.md");
        string? refTempPath = null;

        try
        {
            if (request.ReferenceImageBytes is { Length: > 0 })
            {
                refTempPath = Path.Combine(Path.GetTempPath(), $"heroshot-codex-ref-{Guid.NewGuid():N}.png");
                File.WriteAllBytes(refTempPath, request.ReferenceImageBytes);
                _logger.Info($"[Codex] Reference image temp: {refTempPath} ({request.ReferenceImageBytes.Length} bytes)");
            }

            // Snapshot the child's generated-images dir BEFORE the run so we can attribute the output.
            var genDir = ResolveGeneratedImagesDir();
            var before = Directory.Exists(genDir)
                ? new HashSet<string>(Directory.EnumerateFiles(genDir, "*.png", SearchOption.AllDirectories), StringComparer.OrdinalIgnoreCase)
                : new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            var prompt = BuildPrompt(request.Prompt, refTempPath, codexCfg.EnableWebSearch, request.Width, request.Height);
            var codexExe = string.IsNullOrWhiteSpace(codexCfg.CodexExecutable) ? "codex" : codexCfg.CodexExecutable;
            var args = BuildArguments(codexCfg, verdictPath);

            _logger.Info($"[Codex] Running: {codexExe} {args}");

            var (exitCode, stdout, stderr, timedOut) = RunCodex(codexExe, args, prompt, codexCfg.TimeoutSeconds);

            if (timedOut)
                return Fail($"codex exec timed out after {codexCfg.TimeoutSeconds}s.", stderr, stdout);

            if (exitCode != 0)
                return Fail($"codex exec exited {exitCode}.", stderr, stdout);

            // Harvest with fail-closed attribution.
            var reported = ParseArtifactPath(verdictPath);
            var after = Directory.Exists(genDir)
                ? Directory.EnumerateFiles(genDir, "*.png", SearchOption.AllDirectories).ToList()
                : new List<string>();
            var newFiles = after.Where(f => !before.Contains(f)).ToList();

            var chosen = SelectArtifact(newFiles, reported, before, out var attributionError);
            if (chosen is null)
                return Fail(attributionError ?? "could not attribute a generated image to this run.", stderr, stdout);

            byte[] bytes;
            try { bytes = File.ReadAllBytes(chosen); }
            catch (Exception ex) { return Fail($"failed to read generated image '{chosen}': {ex.Message}", stderr, stdout); }

            if (!HasPngMagic(bytes))
                return Fail($"generated artifact '{chosen}' is not a PNG (magic-byte check failed).", stderr, stdout);

            WarnOnRiskyAspect(bytes, request.Width, request.Height);

            _logger.Info($"[Codex] Image ready: {chosen} ({bytes.Length} bytes)");
            return new HeroShotResponse { Success = true, ImageBytes = bytes };
        }
        catch (Exception ex)
        {
            return new HeroShotResponse { Success = false, Error = $"Codex imagegen failed: {ex.Message}" };
        }
        finally
        {
            TryDelete(refTempPath);
            TryDelete(verdictPath);
        }
    }

    // ── codex process ─────────────────────────────────────────────────────────

    private (int exitCode, string stdout, string stderr, bool timedOut) RunCodex(
        string codexExe, string args, string prompt, int timeoutSeconds)
    {
        using var process = new Process { StartInfo = BuildStartInfo(codexExe, args) };

        var stdout = new StringBuilder();
        var stderr = new StringBuilder();
        process.OutputDataReceived += (_, e) => { if (e.Data is not null) stdout.AppendLine(e.Data); };
        process.ErrorDataReceived  += (_, e) => { if (e.Data is not null) stderr.AppendLine(e.Data); };

        process.Start();

        // Feed the prompt via stdin and close it — the EOF that stops codex hanging on stdin.
        process.StandardInput.Write(prompt);
        process.StandardInput.Close();

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        if (!process.WaitForExit(timeoutSeconds * 1000))
        {
            // Kill only the tree WE started (cmd.exe + its codex child) — never other codex sessions.
            try { process.Kill(entireProcessTree: true); } catch { /* best effort */ }
            try { process.WaitForExit(5000); } catch { /* best effort */ }
            return (-1, stdout.ToString(), stderr.ToString(), true);
        }

        // Let async readers flush.
        process.WaitForExit();
        return (process.ExitCode, stdout.ToString(), stderr.ToString(), false);
    }

    private static ProcessStartInfo BuildStartInfo(string codexExe, string args)
    {
        var isWindows = RuntimeInformation.IsOSPlatform(OSPlatform.Windows);
        var looksLikeDirectExe =
            codexExe.Contains(Path.DirectorySeparatorChar) ||
            codexExe.Contains(Path.AltDirectorySeparatorChar) ||
            codexExe.EndsWith(".exe", StringComparison.OrdinalIgnoreCase);

        ProcessStartInfo psi;
        if (isWindows && !looksLikeDirectExe)
        {
            // On Windows `codex` is an npm .cmd shim; run it through cmd.exe so PATHEXT resolves it.
            psi = new ProcessStartInfo("cmd.exe", $"/c {codexExe} {args}");
        }
        else
        {
            psi = new ProcessStartInfo(codexExe, args);
        }

        psi.RedirectStandardInput = true;
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        return psi;
    }

    private static string BuildArguments(AppConfig.HeroShotConfig.CodexConfig cfg, string verdictPath)
    {
        var sb = new StringBuilder();
        sb.Append("exec");
        sb.Append(" --ephemeral");
        sb.Append(" --skip-git-repo-check");
        sb.Append(" --sandbox workspace-write");
        sb.Append(" -c model_reasoning_effort=").Append(cfg.ReasoningEffort);
        if (cfg.EnableWebSearch)
            sb.Append(" -c web_search=live");
        if (!string.IsNullOrWhiteSpace(cfg.Model))
            sb.Append(" -m ").Append(cfg.Model.Trim());
        if (!string.IsNullOrWhiteSpace(cfg.ExtraArgs))
            sb.Append(' ').Append(cfg.ExtraArgs.Trim());
        sb.Append(" -o ").Append(Q(verdictPath));
        return sb.ToString();
    }

    // ── prompt ──────────────────────────────────────────────────────────────

    /// <param name="width">Target render width; paired with <paramref name="height"/> it fixes the aspect
    /// ratio the publish step center-crops to. Passing it matters: without an explicit ratio the model picks
    /// its own, and anything taller than the target silently loses the head and feet to that crop.</param>
    /// <param name="height">Target render height. See <paramref name="width"/>.</param>
    internal static string BuildPrompt(string corePrompt, string? refTempPath, bool webSearchEnabled, int width, int height)
    {
        var sb = new StringBuilder();
        sb.AppendLine("Use the imagegen skill (the built-in image_gen tool) to generate ONE image.");
        sb.AppendLine();

        if (webSearchEnabled)
        {
            sb.AppendLine("Some equipped items are named in the prompt below with their WoW item IDs. You have web " +
                          "access — before generating, look up any item whose in-game appearance you are unsure of " +
                          "(e.g. https://www.wowhead.com/tbc/item=<id>) so the rendered transmog matches the real model. " +
                          "Do not fall back to generic armor when a specific item is named.");
            sb.AppendLine();
        }

        if (!string.IsNullOrWhiteSpace(refTempPath))
        {
            sb.AppendLine("First, load this local reference image so it is in context:");
            sb.Append("  view_image  ").AppendLine(refTempPath);
            sb.AppendLine();
            sb.AppendLine("Then generate a NEW image (do NOT merely return or minimally edit the reference). " +
                          "Use the reference ONLY as visual guidance for the character's identity, proportions, " +
                          "and pose. Take the armor and weapons from the equipped gear list in the prompt below, " +
                          "not from the reference. The image to generate:");
        }
        else
        {
            sb.AppendLine("Generate the following image:");
        }

        sb.AppendLine();
        sb.AppendLine(corePrompt);
        sb.AppendLine();
        sb.AppendLine("Requirements:");
        if (width > 0 && height > 0)
        {
            var (aspectW, aspectH) = ReduceRatio(width, height);
            var ratio = (double)width / height;
            sb.AppendLine($"- Vertical full-body character portrait, {width}x{height} pixels " +
                          $"(aspect ratio {aspectW}:{aspectH}, width divided by height = {ratio:0.###}).");
            sb.AppendLine($"- The image is afterwards resized and CENTER-CROPPED to exactly {aspectW}:{aspectH}; " +
                          "whatever falls outside that centred region is thrown away. Do NOT generate a frame " +
                          "TALLER than that ratio - a taller frame has its top and bottom cut off, which " +
                          "decapitates the character and removes the feet. If you cannot hit the exact size, " +
                          "err on the side of a WIDER frame: surplus width is cropped away harmlessly.");
            sb.AppendLine($"- Keep the whole character - top of the head, weapons and feet - inside the centred " +
                          $"{aspectW}:{aspectH} region, with visible margin on every side.");
        }
        else
        {
            sb.AppendLine("- Vertical full-body character portrait, portrait orientation (taller than wide).");
        }
        sb.AppendLine("- Produce EXACTLY ONE image.");
        sb.AppendLine("- Do NOT edit, create, or modify any files in the repository or working directory.");
        sb.AppendLine("- After generating, report on its own line the EXACT absolute filesystem path of the " +
                      "single generated image, prefixed with \"ARTIFACT_PATH: \".");
        return sb.ToString();
    }

    // ── attribution / harvest ──────────────────────────────────────────────────

    /// <summary>
    /// Fail-closed selection: require exactly one new image, using the codex-reported path only to
    /// disambiguate. Returns null (with a reason) rather than guessing when attribution is ambiguous.
    /// </summary>
    private static string? SelectArtifact(List<string> newFiles, string? reported, HashSet<string> before, out string? error)
    {
        error = null;

        if (newFiles.Count == 1)
        {
            if (reported is not null && !PathsEqual(newFiles[0], reported))
                // Not fatal — we trust the single observed new file over a possibly-paraphrased report.
                return newFiles[0];
            return newFiles[0];
        }

        if (newFiles.Count == 0)
        {
            // The agent may have written outside the snapshot dir; trust an explicit, existing, non-stale report.
            if (reported is not null && File.Exists(reported) && !before.Contains(reported))
                return reported;
            error = "no new image appeared under the codex generated-images directory and no valid reported path.";
            return null;
        }

        // >= 2 new files: only accept if the reported path pins exactly one of them.
        if (reported is not null)
        {
            var match = newFiles.FirstOrDefault(f => PathsEqual(f, reported));
            if (match is not null) return match;
        }
        error = $"ambiguous attribution: {newFiles.Count} new images appeared and none matched the reported path.";
        return null;
    }

    private static string? ParseArtifactPath(string verdictPath)
    {
        if (!File.Exists(verdictPath)) return null;
        try
        {
            string? last = null;
            foreach (var line in File.ReadLines(verdictPath))
            {
                var idx = line.IndexOf("ARTIFACT_PATH:", StringComparison.OrdinalIgnoreCase);
                if (idx >= 0)
                    last = line[(idx + "ARTIFACT_PATH:".Length)..].Trim().Trim('"', '`', ' ');
            }
            return string.IsNullOrWhiteSpace(last) ? null : last;
        }
        catch { return null; }
    }

    private static string ResolveGeneratedImagesDir()
    {
        var codexHome = Environment.GetEnvironmentVariable("CODEX_HOME");
        if (string.IsNullOrWhiteSpace(codexHome))
            codexHome = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex");
        return Path.Combine(codexHome, "generated_images");
    }

    // ── helpers ────────────────────────────────────────────────────────────────

    private HeroShotResponse Fail(string reason, string stderr, string stdout)
    {
        var detail = !string.IsNullOrWhiteSpace(stderr) ? stderr : stdout;
        detail = detail.Trim();
        if (detail.Length > 400) detail = detail[^400..];
        var msg = string.IsNullOrWhiteSpace(detail) ? reason : $"{reason} :: {detail}";
        _logger.Warn($"[Codex] {msg}");
        return new HeroShotResponse { Success = false, Error = msg };
    }

    /// <summary>
    /// The publish step resizes-to-fill and center-crops to the target ratio, so an image TALLER than the
    /// target loses its top and bottom - exactly where the head and feet are. The cropped .tga still looks
    /// like a valid render, so the loss is invisible downstream; log it here instead of shipping silently.
    /// </summary>
    private void WarnOnRiskyAspect(byte[] png, int targetWidth, int targetHeight)
    {
        if (targetWidth <= 0 || targetHeight <= 0) return;
        if (!TryReadPngSize(png, out var w, out var h) || w <= 0 || h <= 0) return;

        var target = (double)targetWidth / targetHeight;
        var actual = (double)w / h;
        if (actual >= target - AspectTolerance) return;

        var lossPercent = (1.0 - actual / target) * 100.0;
        _logger.Warn(
            $"[Codex] Generated image is {w}x{h} (ratio {actual:0.###}), taller than the " +
            $"{targetWidth}x{targetHeight} target (ratio {target:0.###}). The publish crop will remove about " +
            $"{lossPercent:0.#}% of the height, split between top and bottom - the head and/or feet may be cut off.");
    }

    /// <summary>Reads the dimensions straight out of the PNG IHDR chunk (big-endian ints at offsets 16 and 20),
    /// which avoids decoding the whole image just to check its shape.</summary>
    private static bool TryReadPngSize(byte[] png, out int width, out int height)
    {
        width = 0;
        height = 0;
        if (png.Length < 24) return false;
        width  = (png[16] << 24) | (png[17] << 16) | (png[18] << 8) | png[19];
        height = (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23];
        return true;
    }

    private static (int Width, int Height) ReduceRatio(int width, int height)
    {
        var divisor = Gcd(Math.Abs(width), Math.Abs(height));
        return divisor == 0 ? (width, height) : (width / divisor, height / divisor);
    }

    private static int Gcd(int a, int b)
    {
        while (b != 0) (a, b) = (b, a % b);
        return a;
    }

    private static bool HasPngMagic(byte[] bytes)
    {
        if (bytes.Length < PngMagic.Length) return false;
        for (var i = 0; i < PngMagic.Length; i++)
            if (bytes[i] != PngMagic[i]) return false;
        return true;
    }

    private static bool PathsEqual(string a, string b)
    {
        try { return string.Equals(Path.GetFullPath(a), Path.GetFullPath(b), StringComparison.OrdinalIgnoreCase); }
        catch { return string.Equals(a, b, StringComparison.OrdinalIgnoreCase); }
    }

    private static void TryDelete(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return;
        try { File.Delete(path); } catch { /* best effort */ }
    }

    private static string Q(string value) => $"\"{value.Replace("\"", "\\\"")}\"";
}
