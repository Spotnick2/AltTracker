using AltTracker.RenderPipeline.Infrastructure;

namespace AltTracker.RenderPipeline.Services.BattleNet;

/// <summary>
/// Battle.net API client credentials.
///
/// Deliberately NOT part of AppConfig: appsettings.json is git-tracked, so there must be no
/// deserialization path that could pull a client secret out of it. Credentials come from the
/// environment only.
/// </summary>
public sealed class BattleNetCredentials
{
    // BATTLENET_* is the preferred spelling; BLIZZARD_* is accepted as an alias because it is the
    // de-facto convention in community tooling and is what most existing setups already have set.
    private static readonly string[] ClientIdVariables = ["BATTLENET_CLIENT_ID", "BLIZZARD_CLIENT_ID"];
    private static readonly string[] ClientSecretVariables = ["BATTLENET_CLIENT_SECRET", "BLIZZARD_CLIENT_SECRET"];

    public const string ClientIdVariable = "BATTLENET_CLIENT_ID";
    public const string ClientSecretVariable = "BATTLENET_CLIENT_SECRET";

    private static string? ReadFirstSet(string[] names)
    {
        foreach (var name in names)
        {
            var value = Environment.GetEnvironmentVariable(name);
            if (!string.IsNullOrWhiteSpace(value)) return value;
        }
        return null;
    }

    public string ClientId { get; }
    public string ClientSecret { get; }

    private BattleNetCredentials(string clientId, string clientSecret)
    {
        ClientId = clientId;
        ClientSecret = clientSecret;
    }

    /// <summary>Reads credentials from the environment. Returns null (with a reason) when unset.</summary>
    public static BattleNetCredentials? TryFromEnvironment(out string? reason)
    {
        var id = ReadFirstSet(ClientIdVariables);
        var secret = ReadFirstSet(ClientSecretVariables);

        var missing = new List<string>();
        if (string.IsNullOrWhiteSpace(id)) missing.Add(ClientIdVariable);
        if (string.IsNullOrWhiteSpace(secret)) missing.Add(ClientSecretVariable);

        if (missing.Count > 0)
        {
            reason = $"missing environment variable(s): {string.Join(", ", missing)}. "
                   + "Set them with: setx BATTLENET_CLIENT_ID \"<id>\" and setx BATTLENET_CLIENT_SECRET \"<secret>\", "
                   + "then start a new shell.";
            return null;
        }

        reason = null;
        return new BattleNetCredentials(id!.Trim(), secret!.Trim());
    }

    public static BattleNetCredentials FromEnvironment()
    {
        var creds = TryFromEnvironment(out var reason);
        return creds ?? throw new PipelineDataException($"Blizzard credentials unavailable: {reason}");
    }
}
