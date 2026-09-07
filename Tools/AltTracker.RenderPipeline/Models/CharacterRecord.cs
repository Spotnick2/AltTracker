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

    /// <summary>False when the player has helm display switched off in game. The armory render
    /// honours that toggle but the equipped-item list does not, and the prompt tells the model to
    /// trust the item list over the reference — so without this a character who hides their helm
    /// gets a portrait wearing one. Defaults to true: a record scanned before the addon captured
    /// the flag has no value, and true is the behaviour those records already had.</summary>
    public bool ShowHelm { get; init; } = true;

    /// <summary>False when the player has cloak display switched off. Same reasoning as
    /// <see cref="ShowHelm"/>.</summary>
    public bool ShowCloak { get; init; } = true;
}
