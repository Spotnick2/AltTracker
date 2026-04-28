using System.Text.Json;

namespace AltTracker.RenderPipeline.Services.HeroShot;

public sealed class HeroShotStateStore
{
    private readonly string _stateDir;
    private static readonly JsonSerializerOptions JsonOpts = new() { WriteIndented = true, PropertyNameCaseInsensitive = true };

    public HeroShotStateStore(string tempPath)
    {
        _stateDir = Path.Combine(tempPath, "heroshot");
        Directory.CreateDirectory(_stateDir);
    }

    public HeroShotRenderState? TryLoad(string manifestKey)
    {
        var path = GetStatePath(manifestKey);
        if (!File.Exists(path)) return null;
        try
        {
            var json = File.ReadAllText(path);
            return JsonSerializer.Deserialize<HeroShotRenderState>(json, JsonOpts);
        }
        catch
        {
            return null;
        }
    }

    public void Save(string manifestKey, HeroShotRenderState state)
    {
        var path = GetStatePath(manifestKey);
        File.WriteAllText(path, JsonSerializer.Serialize(state, JsonOpts));
    }

    private string GetStatePath(string manifestKey)
    {
        // manifestKey = "Dreamscythe:1:Kaleid" — sanitize to safe filename
        var safe = string.Concat(manifestKey.Select(c => char.IsLetterOrDigit(c) || c == '_' || c == '-' ? c : '_'));
        return Path.Combine(_stateDir, safe + ".heroshot-state.json");
    }
}
