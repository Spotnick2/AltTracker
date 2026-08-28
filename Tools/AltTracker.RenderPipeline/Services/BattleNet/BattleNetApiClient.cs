using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.RegularExpressions;
using AltTracker.RenderPipeline.Infrastructure;

namespace AltTracker.RenderPipeline.Services.BattleNet;

public sealed record CharacterMedia(string MainRawUrl, long CharacterId, string Source);

/// <summary>
/// Reads the Blizzard Profile API. Everything here is public character data reachable with a
/// client-credentials token.
/// </summary>
public sealed class BattleNetApiClient
{
    // Filename shape on the render CDN, e.g. "45832558-avatar.jpg".
    private static readonly Regex AvatarFileName =
        new(@"^(?<renderId>\d+)-avatar\.jpg$", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private const string RenderHostSuffix = ".worldofwarcraft.com";

    private readonly AppConfig.BattleNetConfig _config;
    private readonly BattleNetTokenProvider _tokens;
    private readonly HttpClient _http;
    private readonly RunLogger _logger;

    private Dictionary<string, string>? _realmSlugsByName;

    public BattleNetApiClient(
        AppConfig.BattleNetConfig config, BattleNetTokenProvider tokens, HttpClient http, RunLogger logger)
    {
        _config = config;
        _tokens = tokens;
        _http = http;
        _logger = logger;
    }

    private string ApiHost => $"https://{_config.Region}.api.blizzard.com";

    /// <summary>
    /// Resolves a SavedVariables realm name to the canonical Blizzard realm slug using the realm
    /// index, rather than guessing at punctuation/casing rules. Falls back to a simple normalization
    /// when the realm is not in the index.
    /// </summary>
    public async Task<string> ResolveRealmSlugAsync(string realmName, CancellationToken ct = default)
    {
        if (_config.RealmSlugOverrides.TryGetValue(realmName, out var overrideSlug)
            && !string.IsNullOrWhiteSpace(overrideSlug))
        {
            return overrideSlug;
        }

        _realmSlugsByName ??= await LoadRealmIndexAsync(ct).ConfigureAwait(false);

        if (_realmSlugsByName.TryGetValue(realmName.Trim(), out var slug))
        {
            return slug;
        }

        var guessed = NormalizeSlug(realmName);
        _logger.Verbose($"[BattleNet] Realm '{realmName}' not in the index; falling back to '{guessed}'.");
        return guessed;
    }

    private async Task<Dictionary<string, string>> LoadRealmIndexAsync(CancellationToken ct)
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var url = $"{ApiHost}/data/wow/realm/index?namespace={_config.RealmNamespace}";

        using var response = await SendAsync(url, ct).ConfigureAwait(false);
        if (response is null || !response.IsSuccessStatusCode)
        {
            _logger.Warn("[BattleNet] Realm index unavailable; realm slugs will be guessed.");
            return map;
        }

        var json = await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
        using var doc = JsonDocument.Parse(json);
        if (!doc.RootElement.TryGetProperty("realms", out var realms)) return map;

        foreach (var realm in realms.EnumerateArray())
        {
            if (!realm.TryGetProperty("slug", out var slugElement)) continue;
            var slug = slugElement.GetString();
            if (string.IsNullOrWhiteSpace(slug)) continue;

            map[slug] = slug;
            if (!realm.TryGetProperty("name", out var name)) continue;

            // Classic returns name as a localized object; a plain string is also tolerated.
            if (name.ValueKind == JsonValueKind.String && name.GetString() is { } plainName)
            {
                map[plainName] = slug;
            }
            else if (name.ValueKind == JsonValueKind.Object
                     && name.TryGetProperty("en_US", out var enUs)
                     && enUs.GetString() is { } enUsName)
            {
                map[enUsName] = slug;
            }
        }

        _logger.Verbose($"[BattleNet] Realm index loaded ({map.Count} name/slug entries).");
        return map;
    }

    /// <summary>
    /// Fetches the character's full-body render URL. Returns null when the character has no armory
    /// presence (wrong game version, never logged out, renamed) - an expected outcome, not an error;
    /// the caller falls back to another reference tier.
    /// </summary>
    public async Task<CharacterMedia?> TryGetCharacterMediaAsync(
        string realmSlug, string characterName, CancellationToken ct = default)
    {
        var encodedName = Uri.EscapeDataString(characterName.ToLowerInvariant());
        var url = $"{ApiHost}/profile/wow/character/{Uri.EscapeDataString(realmSlug)}/{encodedName}"
                + $"/character-media?namespace={_config.Namespace}";

        using var response = await SendAsync(url, ct).ConfigureAwait(false);
        if (response is null) return null;

        if (response.StatusCode == HttpStatusCode.NotFound)
        {
            _logger.Verbose($"[BattleNet] No armory entry for {characterName}-{realmSlug} (404) - the character has never logged out since renders were enabled, or was renamed or deleted.");
            return null;
        }

        if (!response.IsSuccessStatusCode)
        {
            _logger.Warn($"[BattleNet] character-media for {characterName}-{realmSlug} returned "
                       + $"{(int)response.StatusCode} {response.ReasonPhrase}.");
            return null;
        }

        var json = await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        long characterId = 0;
        if (root.TryGetProperty("character", out var character)
            && character.TryGetProperty("id", out var idElement)
            && idElement.TryGetInt64(out var parsedId))
        {
            characterId = parsedId;
        }

        if (!root.TryGetProperty("assets", out var assets) || assets.ValueKind != JsonValueKind.Array)
        {
            return null;
        }

        string? avatarUrl = null;
        foreach (var asset in assets.EnumerateArray())
        {
            var key = asset.TryGetProperty("key", out var k) ? k.GetString() : null;
            var value = asset.TryGetProperty("value", out var v) ? v.GetString() : null;
            if (string.IsNullOrWhiteSpace(value)) continue;

            // Preferred: Blizzard lists the full-body render directly.
            if (string.Equals(key, "main-raw", StringComparison.OrdinalIgnoreCase))
            {
                return new CharacterMedia(value!, characterId, "assets[main-raw]");
            }
            if (string.Equals(key, "avatar", StringComparison.OrdinalIgnoreCase))
            {
                avatarUrl = value;
            }
        }

        // Fallback: derive main-raw from the avatar URL. Deliberately strict - a derivation failure
        // means "unavailable", never an exception.
        if (avatarUrl is not null && TryDeriveMainRawUrl(avatarUrl, out var derived))
        {
            _logger.Verbose($"[BattleNet] Derived main-raw URL from avatar for {characterName}-{realmSlug}.");
            return new CharacterMedia(derived!, characterId, "derived-from-avatar");
        }

        return null;
    }

    /// <summary>
    /// Derives the full-body render URL from the avatar URL, reusing the avatar's host and realm
    /// path rather than rebuilding a CDN URL from SavedVariables data. The shard directory is
    /// recomputed as renderId % 256 instead of trusting the existing path segment.
    /// </summary>
    internal static bool TryDeriveMainRawUrl(string avatarUrl, out string? mainRawUrl)
    {
        mainRawUrl = null;

        if (!Uri.TryCreate(avatarUrl, UriKind.Absolute, out var uri)) return false;
        if (uri.Scheme != Uri.UriSchemeHttps) return false;
        if (!IsRenderCdnHost(uri.Host)) return false;

        var segments = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Length < 2) return false;

        var match = AvatarFileName.Match(segments[^1]);
        if (!match.Success) return false;
        if (!long.TryParse(match.Groups["renderId"].Value, out var renderId)) return false;

        segments[^2] = (renderId % 256).ToString();
        segments[^1] = $"{renderId}-main-raw.png";

        mainRawUrl = $"{uri.Scheme}://{uri.Host}/{string.Join("/", segments)}";
        return true;
    }

    /// <summary>
    /// Whether a host is the character-render CDN. Blizzard serves renders both from
    /// render.worldofwarcraft.com and from region-prefixed hosts such as
    /// render-us.worldofwarcraft.com (the form used in Blizzard's own documentation), so the first
    /// label is matched rather than the whole host - while still refusing any other subdomain.
    /// </summary>
    private static bool IsRenderCdnHost(string host)
    {
        if (!host.EndsWith(RenderHostSuffix, StringComparison.OrdinalIgnoreCase)) return false;

        var dot = host.IndexOf('.');
        if (dot <= 0) return false;

        var firstLabel = host[..dot];
        return firstLabel.Equals("render", StringComparison.OrdinalIgnoreCase)
            || firstLabel.StartsWith("render-", StringComparison.OrdinalIgnoreCase);
    }

    internal static string NormalizeSlug(string realmName)
    {
        var lowered = realmName.Trim().ToLowerInvariant();
        var slug = new string(lowered.Select(ch => char.IsLetterOrDigit(ch) ? ch : '-').ToArray());
        while (slug.Contains("--", StringComparison.Ordinal))
        {
            slug = slug.Replace("--", "-");
        }
        return slug.Trim('-');
    }

    /// <summary>GET with a bearer token, one Retry-After-honouring 429 retry and one 5xx retry.</summary>
    private async Task<HttpResponseMessage?> SendAsync(string url, CancellationToken ct)
    {
        for (var attempt = 0; attempt < 2; attempt++)
        {
            var token = await _tokens.GetTokenAsync(ct).ConfigureAwait(false);
            HttpResponseMessage response;

            using (var request = new HttpRequestMessage(HttpMethod.Get, url))
            {
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
                try
                {
                    response = await _http.SendAsync(request, ct).ConfigureAwait(false);
                }
                catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
                {
                    _logger.Warn($"[BattleNet] Request failed ({ex.GetType().Name}): {url}");
                    if (attempt == 1) return null;
                    continue;
                }
            }

            if (attempt == 0 && response.StatusCode == HttpStatusCode.TooManyRequests)
            {
                var delay = response.Headers.RetryAfter?.Delta ?? TimeSpan.FromSeconds(2);
                _logger.Warn($"[BattleNet] Rate limited; waiting {delay.TotalSeconds:0.#}s.");
                response.Dispose();
                await Task.Delay(delay, ct).ConfigureAwait(false);
                continue;
            }

            if (attempt == 0 && (int)response.StatusCode >= 500)
            {
                _logger.Warn($"[BattleNet] Server error {(int)response.StatusCode}; retrying once.");
                response.Dispose();
                continue;
            }

            return response;
        }

        return null;
    }
}
