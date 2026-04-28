using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using AltTracker.RenderPipeline.Models;

namespace AltTracker.RenderPipeline.Services;

public static class PathTools
{
    private static readonly Regex NonAlphaNum = new("[^a-z0-9]+", RegexOptions.Compiled);
    private static readonly Regex ItemIdRegex = new(@"item:(\d+)", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    public static string SanitizeToken(string? value, string fallback)
    {
        var token = (value ?? "").Trim().ToLowerInvariant();
        token = NonAlphaNum.Replace(token, "_");
        token = token.Trim('_');
        while (token.Contains("__", StringComparison.Ordinal))
        {
            token = token.Replace("__", "_", StringComparison.Ordinal);
        }
        return string.IsNullOrEmpty(token) ? fallback : token;
    }

    public static string BuildOutputBaseName(CharacterRecord character)
    {
        var realm = SanitizeToken(character.Realm, "unknown");
        var account = SanitizeToken(character.Account, "default");
        var name = SanitizeToken(character.Name, "noname");
        return $"{realm}_{account}_{name}";
    }

    public static string BuildManifestKey(CharacterRecord character)
    {
        var realm = string.IsNullOrWhiteSpace(character.Realm) ? "Unknown" : character.Realm.Trim();
        var account = string.IsNullOrWhiteSpace(character.Account) ? "Default" : character.Account.Trim();
        var name = string.IsNullOrWhiteSpace(character.Name) ? "NoName" : character.Name.Trim();
        return $"{realm}:{account}:{name}";
    }

    public static string ComputeGearHash(CharacterRecord c, string renderProfileVersion)
    {
        var sb = new StringBuilder();
        sb.Append(renderProfileVersion).Append('|');
        sb.Append(c.Realm).Append('|').Append(c.Account).Append('|').Append(c.Name).Append('|');
        sb.Append(c.Race).Append('|').Append(c.Gender).Append('|').Append(c.Class).Append('|');
        foreach (var slot in CharacterRecord.GearSlots)
        {
            var id = c.GearItemIds.TryGetValue(slot, out var value) ? value : 0;
            sb.Append(slot).Append(':').Append(id).Append('|');
        }

        var bytes = Encoding.UTF8.GetBytes(sb.ToString());
        var hash = SHA256.HashData(bytes);
        return "sha256:" + Convert.ToHexString(hash).ToLowerInvariant();
    }

    public static int ExtractItemId(string? link)
    {
        if (string.IsNullOrWhiteSpace(link)) return 0;
        var match = ItemIdRegex.Match(link);
        if (!match.Success) return 0;
        return int.TryParse(match.Groups[1].Value, out var id) ? id : 0;
    }

    public static string NormalizeExtension(string? extension, string fallback)
    {
        var raw = (extension ?? "").Trim();
        if (string.IsNullOrEmpty(raw)) return fallback;
        return raw.StartsWith(".", StringComparison.Ordinal) ? raw.ToLowerInvariant() : "." + raw.ToLowerInvariant();
    }

    public static string NormalizeWowPath(string? value)
    {
        var path = (value ?? "").Trim();
        path = path.Replace("/", "\\", StringComparison.Ordinal);
        while (path.Contains(@"\\", StringComparison.Ordinal))
        {
            path = path.Replace(@"\\", @"\", StringComparison.Ordinal);
        }
        return path.Trim('\\');
    }

    public static string CombineWowPath(string root, string fileName)
    {
        var normalizedRoot = NormalizeWowPath(root);
        var normalizedFile = NormalizeWowPath(fileName).Trim('\\');
        if (string.IsNullOrWhiteSpace(normalizedRoot)) return normalizedFile;
        if (string.IsNullOrWhiteSpace(normalizedFile)) return normalizedRoot;
        return normalizedRoot + @"\" + normalizedFile;
    }

    public static bool IsValidWowAddonImagePath(string? imagePath)
    {
        var normalized = NormalizeWowPath(imagePath);
        if (string.IsNullOrWhiteSpace(normalized)) return false;
        if (Path.IsPathRooted(normalized)) return false;
        if (normalized.Contains("..", StringComparison.Ordinal)) return false;
        return normalized.StartsWith(@"Interface\AddOns\", StringComparison.OrdinalIgnoreCase);
    }
}
