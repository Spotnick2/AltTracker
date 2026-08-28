using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using AltTracker.RenderPipeline.Infrastructure;

namespace AltTracker.RenderPipeline.Services.BattleNet;

/// <summary>
/// OAuth client-credentials token provider.
///
/// character-media is PUBLIC character data, so the client-credentials grant is sufficient — the
/// authorization-code flow is only needed for account-bound endpoints such as /profile/user/wow.
///
/// The token is a secret: it is never logged, never persisted, and only ever held in memory.
/// </summary>
public sealed class BattleNetTokenProvider
{
    private const string TokenEndpoint = "https://oauth.battle.net/token";

    private readonly BattleNetCredentials _credentials;
    private readonly HttpClient _http;
    private readonly RunLogger _logger;

    private string? _token;
    private DateTimeOffset _expiresAtUtc = DateTimeOffset.MinValue;

    public BattleNetTokenProvider(BattleNetCredentials credentials, HttpClient http, RunLogger logger)
    {
        _credentials = credentials;
        _http = http;
        _logger = logger;
    }

    public async Task<string> GetTokenAsync(CancellationToken ct = default)
    {
        if (_token is not null && DateTimeOffset.UtcNow < _expiresAtUtc)
        {
            return _token;
        }

        using var request = new HttpRequestMessage(HttpMethod.Post, TokenEndpoint);
        var basic = Convert.ToBase64String(
            Encoding.ASCII.GetBytes($"{_credentials.ClientId}:{_credentials.ClientSecret}"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Basic", basic);
        request.Content = new FormUrlEncodedContent(
            new Dictionary<string, string> { ["grant_type"] = "client_credentials" });

        using var response = await _http.SendAsync(request, ct).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            // Never echo the response body: it can contain credential material.
            throw new PipelineDataException(
                $"Blizzard token request failed: {(int)response.StatusCode} {response.ReasonPhrase}. "
                + $"Check {BattleNetCredentials.ClientIdVariable}/{BattleNetCredentials.ClientSecretVariable}.");
        }

        var json = await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        if (!root.TryGetProperty("access_token", out var tokenElement))
        {
            throw new PipelineDataException("Blizzard token response contained no access_token.");
        }

        var expiresIn = root.TryGetProperty("expires_in", out var e) && e.TryGetInt32(out var secs)
            ? secs
            : 3600;

        _token = tokenElement.GetString();
        // 60s safety margin so a long run cannot straddle expiry.
        _expiresAtUtc = DateTimeOffset.UtcNow.AddSeconds(Math.Max(120, expiresIn) - 60);
        _logger.Verbose($"[BattleNet] Access token acquired (expires in {expiresIn}s).");

        return _token ?? throw new PipelineDataException("Blizzard access_token was null.");
    }
}
