namespace AltTracker.RenderPipeline.Models;

public sealed class CharacterRecord
{
    public static readonly string[] GearSlots =
    [
        "head","neck","shoulder","back","chest","wrist","hands","waist",
        "legs","feet","ring1","ring2","trinket1","trinket2","mainhand","offhand","ranged"
    ];

    public string Guid { get; init; } = "";
    public string Name { get; init; } = "";
    public string Realm { get; init; } = "";
    public string Account { get; init; } = "";
    public string Faction { get; init; } = "";
    public string Race { get; init; } = "";
    public string Gender { get; init; } = "";
    public string Class { get; init; } = "";
    public int Level { get; init; }
    public long LastUpdateEpoch { get; init; }
    /// <summary>Epoch stamped by the addon's /alts update-reference when it captured a fresh
    /// in-game screenshot. The render pipeline matches this to a Screenshots/ file (by mtime) and
    /// prefers it as the reference over the stale saved one. 0 = never captured in-game.</summary>
    public long ReferenceShotEpoch { get; init; }
    public IReadOnlyDictionary<string, int> GearItemIds { get; init; } = new Dictionary<string, int>();
    public IReadOnlyDictionary<string, string> GearLinks { get; init; } = new Dictionary<string, string>();
    /// <summary>Per-slot item name from gearname_ — synced cross-account, so present even when the
    /// local-only gearlink_ has been stripped on a synced record. Preferred source for item names.</summary>
    public IReadOnlyDictionary<string, string> GearNames { get; init; } = new Dictionary<string, string>();
    /// <summary>Per-slot item subtype captured in-client from GetItemInfo (e.g. "Dagger", "Mail").
    /// Authoritative weapon/armor type; empty for slots scanned before this field existed.</summary>
    public IReadOnlyDictionary<string, string> GearSubTypes { get; init; } = new Dictionary<string, string>();
}
