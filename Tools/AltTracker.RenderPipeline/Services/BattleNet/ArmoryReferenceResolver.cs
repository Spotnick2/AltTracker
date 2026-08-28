using System.Security.Cryptography;
using System.Text;
using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Models;
using AltTracker.RenderPipeline.Services.HeroShot;

namespace AltTracker.RenderPipeline.Services.BattleNet;

/// <summary>Outcome of resolving a character's Blizzard render into a usable reference image.</summary>
public sealed record ArmoryReference(
    string PreparedPath, string RawPath, string ContentHash, bool Changed, string RenderUrl);

/// <summary>
/// Orchestrates armory lookup -> render download -> reference preparation.
///
/// Results are memoized per run, so the --refresh-blizzard preflight and the later render pass
/// share a single network fetch per character.
/// </summary>
public sealed class ArmoryReferenceResolver : IDisposable
{
    private readonly AppConfig _config;
    private readonly RunLogger _logger;
    private readonly HttpClient _http;
    private readonly BattleNetApiClient _api;
    private readonly CharacterRenderCache _cache;
    private readonly Dictionary<string, ArmoryReference?> _memo = new(StringComparer.OrdinalIgnoreCase);

    public bool Available { get; }
    public string? UnavailableReason { get; }

    private ArmoryReferenceResolver(
        AppConfig config, RunLogger logger, HttpClient http,
        BattleNetApiClient api, CharacterRenderCache cache)
    {
        _config = config;
        _logger = logger;
        _http = http;
        _api = api;
        _cache = cache;
        Available = true;
    }

    private ArmoryReferenceResolver(AppConfig config, RunLogger logger, string reason)
    {
        _config = config;
        _logger = logger;
        _http = null!;
        _api = null!;
        _cache = null!;
        Available = false;
        UnavailableReason = reason;
    }

    public static ArmoryReferenceResolver Create(AppConfig config, RunLogger logger)
    {
        var blizzard = config.BattleNet;

        if (!blizzard.Enabled)
        {
            return new ArmoryReferenceResolver(config, logger, "BattleNet.Enabled is false");
        }

        var credentials = BattleNetCredentials.TryFromEnvironment(out var reason);
        if (credentials is null)
        {
            return new ArmoryReferenceResolver(config, logger, reason ?? "credentials unavailable");
        }

        var http = new HttpClient { Timeout = TimeSpan.FromSeconds(Math.Max(10, blizzard.TimeoutSeconds)) };
        http.DefaultRequestHeaders.UserAgent.ParseAdd("AltTracker-RenderPipeline/1.0");

        var tokens = new BattleNetTokenProvider(credentials, http, logger);
        var api = new BattleNetApiClient(blizzard, tokens, http, logger);

        var cacheDirectory = string.IsNullOrWhiteSpace(blizzard.CacheDirectory)
            ? Path.Combine(config.TempPath, "blizzard")
            : blizzard.CacheDirectory;
        var cache = new CharacterRenderCache(cacheDirectory, http, logger);

        return new ArmoryReferenceResolver(config, logger, http, api, cache);
    }

    /// <summary>
    /// Resolves the prepared reference image for a character, or null when the armory has nothing
    /// for it (wrong game version, never logged out, renamed). Never throws for an expected miss.
    /// </summary>
    public ArmoryReference? TryResolve(CharacterRecord character, string manifestKey, string outputBaseName)
    {
        if (!Available) return null;

        if (_memo.TryGetValue(manifestKey, out var memoized))
        {
            return memoized;
        }

        ArmoryReference? result = null;
        try
        {
            result = ResolveCore(character, manifestKey, outputBaseName).GetAwaiter().GetResult();
        }
        catch (Exception ex)
        {
            _logger.Warn($"[BattleNet] Reference resolution failed for {manifestKey}: {ex.Message}");
        }

        _memo[manifestKey] = result;
        return result;
    }

    private async Task<ArmoryReference?> ResolveCore(
        CharacterRecord character, string manifestKey, string outputBaseName)
    {
        if (string.IsNullOrWhiteSpace(character.Realm) || string.IsNullOrWhiteSpace(character.Name))
        {
            return null;
        }

        var slug = await _api.ResolveRealmSlugAsync(character.Realm).ConfigureAwait(false);
        var media = await _api.TryGetCharacterMediaAsync(slug, character.Name).ConfigureAwait(false);
        if (media is null) return null;

        var cacheId = CharacterRenderCache.CacheId(manifestKey, outputBaseName);
        var cached = await _cache.FetchAsync(cacheId, media.MainRawUrl).ConfigureAwait(false);
        if (cached is null) return null;

        // The prepared file's identity covers BOTH the preprocessing settings and the render's
        // content hash.
        //
        // Settings, because keying only on the render would mean a change to
        // background/padding/threshold/target size never took effect: an unchanged (304) download
        // would keep serving the old prepared PNG forever, and its fingerprint feeds the render
        // signature, so nothing downstream would notice either.
        //
        // Content hash, because the cache metadata is persisted at download time, before this
        // preparation runs. If a changed render downloads but preprocessing then fails, the next
        // run revalidates to 304 (the stored ETag already matches the new bytes) so Changed is
        // false - and with a settings-only name the stale prepared file still exists, so
        // preparation is skipped and the new render is silently lost for good. Naming the file
        // after the content it was built from makes that failure retry instead.
        var contentTag = string.IsNullOrEmpty(cached.ContentHash) ? "nohash" : cached.ContentHash[..8];
        var cacheDirectory = Path.GetDirectoryName(_cache.RenderPathFor(cacheId))!;
        var preparedPath = Path.Combine(
            cacheDirectory, $"{cacheId}-reference-{PreprocessingTag()}-{contentTag}.png");

        // Re-prepare when the render changed or this exact variant has not been built yet.
        if (cached.Changed || !File.Exists(preparedPath))
        {
            var prepared = ReferenceImagePreprocessor.TryPrepare(
                cached.LocalPath,
                preparedPath,
                _config.BattleNet.ReferenceBackground,
                _config.BattleNet.PaddingFraction,
                _config.BattleNet.AlphaThreshold,
                _config.HeroShot.Width,
                _config.HeroShot.Height,
                _logger);

            if (!prepared) return null;

            // Drop superseded variants for this character so the cache does not grow a file per
            // render revision and settings permutation.
            foreach (var stale in Directory.EnumerateFiles(cacheDirectory, $"{cacheId}-reference-*.png"))
            {
                if (string.Equals(stale, preparedPath, StringComparison.OrdinalIgnoreCase)) continue;
                try { File.Delete(stale); }
                catch (Exception ex) { _logger.Verbose($"[BattleNet] Could not remove {stale}: {ex.Message}"); }
            }
        }

        return new ArmoryReference(
            preparedPath, cached.LocalPath, cached.ContentHash, cached.Changed, media.MainRawUrl);
    }

    /// <summary>Short hash of every setting that affects the prepared reference image.</summary>
    private string PreprocessingTag()
    {
        var b = _config.BattleNet;
        var canonical = string.Join('|',
            b.ReferenceBackground, b.PaddingFraction.ToString("R"), b.AlphaThreshold,
            _config.HeroShot.Width, _config.HeroShot.Height);
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(canonical));
        return Convert.ToHexString(hash)[..8].ToLowerInvariant();
    }

    /// <summary>
    /// Preflight for --refresh-armory: returns the manifest keys whose armory render differs from
    /// what was last rendered. Needed because RenderPlanner drops unchanged characters before the
    /// render adapter runs, so a remote-only change could otherwise never create a job.
    /// </summary>
    public HashSet<string> FindChangedCharacters(
        IReadOnlyList<CharacterRecord> characters, HeroShotStateStore stateStore)
    {
        var changed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (!Available) return changed;

        foreach (var character in characters)
        {
            var manifestKey = PathTools.BuildManifestKey(character);
            var baseName = PathTools.BuildOutputBaseName(character);

            // Mirror the adapter, which skips armory resolution when an explicit override exists.
            // Without this the stored fingerprint belongs to the override image and never matches
            // the armory one, so the character would be queued on every single refresh and churn
            // through conversion and a manifest rewrite each time.
            if (_config.HeroShot.CharacterReferenceImages.ContainsKey(manifestKey))
            {
                _logger.Verbose($"[BattleNet] {manifestKey} uses an explicit reference override; not checked.");
                continue;
            }

            var reference = TryResolve(character, manifestKey, baseName);
            if (reference is null) continue;

            var priorState = stateStore.TryLoad(manifestKey);
            var priorFingerprint = priorState?.ReferenceFingerprint ?? "";
            var currentFingerprint = HeroShotSignatureBuilder.ComputeFileFingerprint(reference.PreparedPath);

            if (!string.Equals(priorFingerprint, currentFingerprint, StringComparison.Ordinal))
            {
                changed.Add(manifestKey);
                _logger.Info(priorFingerprint.Length == 0
                    ? $"[BattleNet] {manifestKey}: no portrait generated from an armory render yet."
                    : $"[BattleNet] {manifestKey}: armory render differs from the one last rendered.");
            }
        }

        return changed;
    }

    public void Dispose() => _http?.Dispose();
}
