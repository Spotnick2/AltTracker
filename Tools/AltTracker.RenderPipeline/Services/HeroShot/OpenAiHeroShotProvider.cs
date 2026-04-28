using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using AltTracker.RenderPipeline.Infrastructure;

namespace AltTracker.RenderPipeline.Services.HeroShot;

public sealed class OpenAiHeroShotProvider : IHeroShotRenderProvider
{
    private readonly AppConfig.HeroShotConfig _cfg;
    private readonly RunLogger _logger;
    private readonly string _apiKey;
    private static readonly HttpClient HttpClient = new();

    public string ProviderId => "openai";

    public OpenAiHeroShotProvider(AppConfig.HeroShotConfig cfg, RunLogger logger)
    {
        _cfg = cfg;
        _logger = logger;
        _apiKey = Environment.GetEnvironmentVariable(_cfg.ApiKeyEnvVar) ?? "";
        if (string.IsNullOrWhiteSpace(_apiKey))
        {
            throw new PipelineDataException(
                $"HeroShot: OpenAI API key not found in env var '{_cfg.ApiKeyEnvVar}'. " +
                $"Set it with: $env:{_cfg.ApiKeyEnvVar}='sk-...'");
        }
    }

    public async Task<HeroShotResponse> GenerateAsync(HeroShotRequest request, CancellationToken cancellationToken = default)
    {
        var size = NormalizeSize(request.Width, request.Height);
        var model = string.IsNullOrWhiteSpace(_cfg.Model) ? "gpt-image-1" : _cfg.Model.Trim();
        var baseUrl = string.IsNullOrWhiteSpace(_cfg.ApiBaseUrl) ? "https://api.openai.com/v1" : _cfg.ApiBaseUrl.TrimEnd('/');
        var useEdits = model.Equals("gpt-image-1", StringComparison.OrdinalIgnoreCase) && request.ReferenceImageBytes is { Length: > 0 };
        var guidedPrompt = AppendAspectGuidance(request.Prompt, request.Width, request.Height);

        _logger.Info($"[HeroShot] OpenAI request: model={model}, size={size}, useEdits={useEdits}, promptLen={guidedPrompt.Length}");

        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(TimeSpan.FromSeconds(Math.Max(30, _cfg.TimeoutSeconds)));

        try
        {
            byte[] imageBytes;
            string? revisedPrompt = null;

            if (useEdits)
            {
                (imageBytes, revisedPrompt) = await CallEditsEndpointAsync(baseUrl, model, size, request, guidedPrompt, cts.Token);
            }
            else
            {
                (imageBytes, revisedPrompt) = await CallGenerationsEndpointAsync(baseUrl, model, size, request, guidedPrompt, cts.Token);
            }

            return new HeroShotResponse
            {
                Success = true,
                ImageBytes = imageBytes,
                RevisedPrompt = revisedPrompt
            };
        }
        catch (OperationCanceledException)
        {
            return new HeroShotResponse { Success = false, Error = "OpenAI request timed out." };
        }
        catch (Exception ex)
        {
            return new HeroShotResponse { Success = false, Error = $"OpenAI request failed: {ex.Message}" };
        }
    }

    private async Task<(byte[] ImageBytes, string? RevisedPrompt)> CallEditsEndpointAsync(
        string baseUrl, string model, string size, HeroShotRequest request, string prompt, CancellationToken ct)
    {
        var url = $"{baseUrl}/images/edits";
        _logger.Info($"[HeroShot] POST {url} (multipart, reference={request.ReferenceImageName})");

        using var content = new MultipartFormDataContent();
        content.Add(new StringContent(model), "model");
        content.Add(new StringContent(prompt), "prompt");
        content.Add(new StringContent("1"), "n");
        content.Add(new StringContent(size), "size");

        var imageContent = new ByteArrayContent(request.ReferenceImageBytes!);
        imageContent.Headers.ContentType = new MediaTypeHeaderValue("image/png");
        content.Add(imageContent, "image", request.ReferenceImageName);

        using var req = new HttpRequestMessage(HttpMethod.Post, url) { Content = content };
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _apiKey);

        var resp = await HttpClient.SendAsync(req, ct);
        return await ParseImageResponseAsync(resp, ct);
    }

    private async Task<(byte[] ImageBytes, string? RevisedPrompt)> CallGenerationsEndpointAsync(
        string baseUrl, string model, string size, HeroShotRequest request, string prompt, CancellationToken ct)
    {
        var url = $"{baseUrl}/images/generations";
        _logger.Info($"[HeroShot] POST {url} (json, model={model})");

        var isDallE3 = model.StartsWith("dall-e-3", StringComparison.OrdinalIgnoreCase);
        var body = new Dictionary<string, object>
        {
            ["model"] = model,
            ["prompt"] = prompt,
            ["n"] = 1,
            ["size"] = size,
            ["response_format"] = "b64_json",
        };
        if (isDallE3)
        {
            body["quality"] = "hd";
            body["style"] = "vivid";
        }

        var json = JsonSerializer.Serialize(body);
        using var req = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _apiKey);

        var resp = await HttpClient.SendAsync(req, ct);
        return await ParseImageResponseAsync(resp, ct);
    }

    private async Task<(byte[] ImageBytes, string? RevisedPrompt)> ParseImageResponseAsync(HttpResponseMessage resp, CancellationToken ct)
    {
        var body = await resp.Content.ReadAsStringAsync(ct);
        if (!resp.IsSuccessStatusCode)
        {
            throw new Exception($"HTTP {(int)resp.StatusCode}: {body}");
        }

        using var doc = JsonDocument.Parse(body);
        var root = doc.RootElement;

        if (!root.TryGetProperty("data", out var dataArr) || dataArr.GetArrayLength() == 0)
        {
            throw new Exception($"No data in response: {body}");
        }

        var first = dataArr[0];
        string? b64 = null;
        string? revisedPrompt = null;

        if (first.TryGetProperty("b64_json", out var b64El))
            b64 = b64El.GetString();
        if (first.TryGetProperty("revised_prompt", out var rpEl))
            revisedPrompt = rpEl.GetString();

        if (string.IsNullOrWhiteSpace(b64))
            throw new Exception($"Empty b64_json in response: {body[..Math.Min(200, body.Length)]}");

        return (Convert.FromBase64String(b64), revisedPrompt);
    }

    private static string NormalizeSize(int width, int height)
    {
        if (width == 1024 && height == 1024) return "1024x1024";
        if (width == 1536 && height == 1024) return "1536x1024";
        if (width == 1024 && height == 1536) return "1024x1536";
        if (width == 1792 && height == 1024) return "1792x1024";
        if (width == 1024 && height == 1792) return "1024x1792";
        return "1024x1024";
    }

    private static string AppendAspectGuidance(string prompt, int width, int height)
    {
        if (string.IsNullOrWhiteSpace(prompt)) return prompt;
        if (width <= 0 || height <= 0) return prompt;
        var ratio = (double)width / height;
        return $"{prompt} Compose for a {width}:{height} ({ratio:0.###}) portrait aspect ratio with centered subject and safe edge space for UI overlays.";
    }
}
