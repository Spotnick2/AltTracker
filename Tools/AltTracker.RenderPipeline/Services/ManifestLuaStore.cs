using System.Text;
using System.Text.RegularExpressions;
using AltTracker.RenderPipeline.Models;

namespace AltTracker.RenderPipeline.Services;

public sealed class ManifestLuaStore
{
    private static readonly Regex EntryRegex = new(@"\[""(?<key>[^""]+)""\]\s*=\s*\{(?<body>.*?)\},", RegexOptions.Singleline | RegexOptions.Compiled);
    private static readonly Regex FieldRegex = new(@"(?m)^\s*(?<name>\w+)\s*=\s*""(?<value>.*?)""\s*,?\s*$", RegexOptions.Compiled);

    public IReadOnlyDictionary<string, ManifestEntry> Read(string path, RunLogger logger)
    {
        if (!File.Exists(path))
        {
            logger.Verbose($"Manifest not found, starting empty: {path}");
            return new Dictionary<string, ManifestEntry>(StringComparer.OrdinalIgnoreCase);
        }

        var text = File.ReadAllText(path);
        var map = new Dictionary<string, ManifestEntry>(StringComparer.OrdinalIgnoreCase);

        foreach (Match m in EntryRegex.Matches(text))
        {
            var key = UnescapeLua(m.Groups["key"].Value);
            var body = m.Groups["body"].Value;
            var fields = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (Match f in FieldRegex.Matches(body))
            {
                fields[f.Groups["name"].Value] = UnescapeLua(f.Groups["value"].Value);
            }

            map[key] = new ManifestEntry
            {
                Image = fields.GetValueOrDefault("image", ""),
                GeneratedAt = fields.GetValueOrDefault("generatedAt", ""),
                GearHash = fields.GetValueOrDefault("gearHash", ""),
                Mode = fields.GetValueOrDefault("mode", ""),
                Width = fields.GetValueOrDefault("width", ""),
                Height = fields.GetValueOrDefault("height", ""),
                Style = fields.GetValueOrDefault("style", ""),
                Signature = fields.GetValueOrDefault("signature", "")
            };
        }

        logger.Verbose($"Manifest entries loaded: {map.Count}");
        return map;
    }

    public bool Write(string path, IReadOnlyDictionary<string, ManifestEntry> entries, RunLogger logger)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var sb = new StringBuilder();
            sb.AppendLine("AltTrackerRenderManifest = {");

            foreach (var kv in entries.OrderBy(k => k.Key, StringComparer.OrdinalIgnoreCase))
            {
                if (!PathTools.IsValidWowAddonImagePath(kv.Value.Image))
                {
                    throw new InvalidOperationException($"Invalid addon image path in manifest entry '{kv.Key}': {kv.Value.Image}");
                }
                sb.AppendLine($"    [\"{EscapeLua(kv.Key)}\"] = {{");
                sb.AppendLine($"        image = \"{EscapeLua(kv.Value.Image)}\",");
                sb.AppendLine($"        generatedAt = \"{EscapeLua(kv.Value.GeneratedAt)}\",");
                sb.AppendLine($"        gearHash = \"{EscapeLua(kv.Value.GearHash)}\",");
                sb.AppendLine($"        mode = \"{EscapeLua(kv.Value.Mode)}\",");
                if (!string.IsNullOrWhiteSpace(kv.Value.Width))
                    sb.AppendLine($"        width = \"{EscapeLua(kv.Value.Width)}\",");
                if (!string.IsNullOrWhiteSpace(kv.Value.Height))
                    sb.AppendLine($"        height = \"{EscapeLua(kv.Value.Height)}\",");
                if (!string.IsNullOrWhiteSpace(kv.Value.Style))
                    sb.AppendLine($"        style = \"{EscapeLua(kv.Value.Style)}\",");
                if (!string.IsNullOrWhiteSpace(kv.Value.Signature))
                    sb.AppendLine($"        signature = \"{EscapeLua(kv.Value.Signature)}\",");
                sb.AppendLine("    },");
            }

            sb.AppendLine("}");

            var tempPath = path + ".tmp";
            File.WriteAllText(tempPath, sb.ToString());
            File.Move(tempPath, path, overwrite: true);
            return true;
        }
        catch (Exception ex)
        {
            logger.Error($"Manifest write error: {ex.Message}");
            return false;
        }
    }

    private static string EscapeLua(string s) =>
        s.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal);

    private static string UnescapeLua(string s) =>
        s.Replace("\\\"", "\"", StringComparison.Ordinal).Replace("\\\\", "\\", StringComparison.Ordinal);
}
