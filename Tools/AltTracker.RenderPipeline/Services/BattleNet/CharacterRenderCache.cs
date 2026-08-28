using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using AltTracker.RenderPipeline.Infrastructure;

namespace AltTracker.RenderPipeline.Services.BattleNet;

/// <summary>Result of a cache fetch. <paramref name="Changed"/> is false when the CDN answered 304.</summary>
public sealed record CachedRender(string LocalPath, bool Changed, string ContentHash);

/// <summary>
/// Downloads and caches the full-body render, revalidating with If-None-Match.
///
/// Freshness note: the render URL embeds the CHARACTER id, not a per-render id, so the URL is
/// stable across gear changes - only the bytes at that URL change. Detecting a new render therefore
/// depends on the ETag/content hash, never on the URL changing. (Verified 2026-08-28: a conditional
/// GET on an unchanged render returns 304 with 0 bytes.)
/// </summary>
public sealed class CharacterRenderCache
{
    private const long MaxDownloadBytes = 16L * 1024 * 1024;

    private readonly string _cacheDirectory;
    private readonly HttpClient _http;
    private readonly RunLogger _logger;

    public CharacterRenderCache(string cacheDirectory, HttpClient http, RunLogger logger)
    {
        _cacheDirectory = cacheDirectory;
        _http = http;
        _logger = logger;
        Directory.CreateDirectory(_cacheDirectory);
    }

    /// <summary>
    /// Cache identity for a character. Includes a hash of the manifest key because
    /// PathTools.SanitizeToken strips non-ASCII and can collapse distinct names to the same token.
    /// </summary>
    public static string CacheId(string manifestKey, string outputBaseName)
    {
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(manifestKey)))[..8].ToLowerInvariant();
        return $"{outputBaseName}-{hash}";
    }

    public string RenderPathFor(string cacheId) => Path.Combine(_cacheDirectory, $"{cacheId}.png");

    private string MetaPathFor(string cacheId) => Path.Combine(_cacheDirectory, $"{cacheId}.meta.json");

    /// <summary>Returns the cached render without touching the network, or null if absent.</summary>
    public CachedRender? TryGetCached(string cacheId)
    {
        var path = RenderPathFor(cacheId);
        if (!File.Exists(path)) return null;
        var meta = ReadMeta(cacheId);
        return new CachedRender(path, Changed: false, ContentHash: meta?.ContentHash ?? "");
    }

    /// <summary>
    /// Fetches the render, revalidating against the stored ETag. On any transient failure the
    /// last-known-good cached copy is returned rather than falling through to a different reference
    /// tier - otherwise the reference fingerprint oscillates between tiers and triggers repeated
    /// paid regenerations.
    /// </summary>
    public async Task<CachedRender?> FetchAsync(string cacheId, string url, CancellationToken ct = default)
    {
        var path = RenderPathFor(cacheId);
        var meta = ReadMeta(cacheId);
        var haveCached = File.Exists(path);

        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        if (haveCached && !string.IsNullOrWhiteSpace(meta?.ETag))
        {
            request.Headers.TryAddWithoutValidation("If-None-Match", meta!.ETag);
        }

        HttpResponseMessage response;
        try
        {
            response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct)
                                  .ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            _logger.Warn($"[BattleNet] Render download failed ({ex.GetType().Name}); "
                       + (haveCached ? "using last-known-good cached render." : "no cached render available."));
            return haveCached ? new CachedRender(path, false, meta?.ContentHash ?? "") : null;
        }

        using (response)
        {
            if (response.StatusCode == HttpStatusCode.NotModified && haveCached)
            {
                _logger.Verbose($"[BattleNet] Render unchanged (304): {cacheId}");
                return new CachedRender(path, Changed: false, ContentHash: meta?.ContentHash ?? "");
            }

            if (!response.IsSuccessStatusCode)
            {
                _logger.Warn($"[BattleNet] Render request returned {(int)response.StatusCode} for {cacheId}; "
                           + (haveCached ? "using last-known-good cached render." : "no cached render available."));
                return haveCached ? new CachedRender(path, false, meta?.ContentHash ?? "") : null;
            }

            if (response.Content.Headers.ContentLength is > MaxDownloadBytes)
            {
                _logger.Warn($"[BattleNet] Render for {cacheId} exceeds {MaxDownloadBytes} bytes; skipping.");
                return haveCached ? new CachedRender(path, false, meta?.ContentHash ?? "") : null;
            }

            var bytes = await response.Content.ReadAsByteArrayAsync(ct).ConfigureAwait(false);
            if (bytes.Length > MaxDownloadBytes || bytes.Length < 128)
            {
                _logger.Warn($"[BattleNet] Render for {cacheId} had implausible size ({bytes.Length} bytes); skipping.");
                return haveCached ? new CachedRender(path, false, meta?.ContentHash ?? "") : null;
            }

            if (!ReferenceImagePreprocessor.LooksLikePng(bytes))
            {
                _logger.Warn($"[BattleNet] Render for {cacheId} was not a PNG; skipping.");
                return haveCached ? new CachedRender(path, false, meta?.ContentHash ?? "") : null;
            }

            var contentHash = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
            var unchanged = haveCached && string.Equals(contentHash, meta?.ContentHash, StringComparison.Ordinal);

            // Write to a temp file and promote atomically so an interrupted run cannot leave a
            // half-written PNG that later looks like a valid cached render.
            var tempPath = path + ".tmp";
            await File.WriteAllBytesAsync(tempPath, bytes, ct).ConfigureAwait(false);
            File.Move(tempPath, path, overwrite: true);

            WriteMeta(cacheId, new CacheMeta
            {
                Url = url,
                ETag = response.Headers.ETag?.Tag,
                LastModified = response.Content.Headers.LastModified?.ToString("O"),
                ContentHash = contentHash,
                FetchedAt = DateTimeOffset.UtcNow.ToString("O")
            });

            _logger.Info($"[BattleNet] Render {(unchanged ? "re-downloaded (identical)" : "updated")}: "
                       + $"{cacheId} ({bytes.Length} bytes)");
            return new CachedRender(path, Changed: !unchanged, ContentHash: contentHash);
        }
    }

    private CacheMeta? ReadMeta(string cacheId)
    {
        try
        {
            var metaPath = MetaPathFor(cacheId);
            if (!File.Exists(metaPath)) return null;
            return JsonSerializer.Deserialize<CacheMeta>(File.ReadAllText(metaPath));
        }
        catch
        {
            return null;
        }
    }

    private void WriteMeta(string cacheId, CacheMeta meta)
    {
        try
        {
            File.WriteAllText(
                MetaPathFor(cacheId),
                JsonSerializer.Serialize(meta, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception ex)
        {
            _logger.Verbose($"[BattleNet] Could not persist cache metadata for {cacheId}: {ex.Message}");
        }
    }

    /// <summary>Cache metadata. Holds only public values - never a token or credential.</summary>
    public sealed class CacheMeta
    {
        public string Url { get; set; } = "";
        public string? ETag { get; set; }
        public string? LastModified { get; set; }
        public string ContentHash { get; set; } = "";
        public string FetchedAt { get; set; } = "";
    }
}
