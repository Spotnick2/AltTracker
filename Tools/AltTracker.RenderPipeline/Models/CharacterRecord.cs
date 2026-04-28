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
    public IReadOnlyDictionary<string, int> GearItemIds { get; init; } = new Dictionary<string, int>();
    public IReadOnlyDictionary<string, string> GearLinks { get; init; } = new Dictionary<string, string>();
}
