using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Models;
using AltTracker.RenderPipeline.Services;
using AltTracker.RenderPipeline.Services.HeroShot;

namespace AltTracker.RenderPipeline.Tests;

/// <summary>
/// A character who hides their helm in game was still rendered wearing it. The armory reference
/// honours the toggle, but the prompt declares the equipped-item list authoritative over the
/// reference for armor, so the helmet in the item list won and the portrait grew a helmet the
/// player never sees. Enabling web search made it worse, not better, because the model then
/// looked the helmet up and rendered it faithfully.
/// </summary>
public class HiddenSlotTests
{
    private static CharacterRecord Character(bool showHelm = true, bool showCloak = true) => new()
    {
        Realm = "Dreamscythe",
        Account = "1",
        Name = "Drakuzo",
        Race = "Orc",
        Gender = "Female",
        Class = "WARLOCK",
        ShowHelm = showHelm,
        ShowCloak = showCloak,
        GearItemIds = new Dictionary<string, int>
        {
            ["head"] = 30212, ["back"] = 28570, ["chest"] = 30107, ["shoulder"] = 28967,
        },
        GearNames = new Dictionary<string, string>
        {
            ["head"] = "Hood of the Corruptor",
            ["back"] = "Shadow-Cloak of Dalaran",
            ["chest"] = "Vestments of the Sea-Witch",
            ["shoulder"] = "Voidheart Mantle",
        },
    };

    private static string Prompt(CharacterRecord c) =>
        HeroShotPromptBuilder.Build(c, "realistic", hasReferenceImage: true);

    // ── gear manifest ────────────────────────────────────────────────────────

    [Fact]
    public void ListsTheHeadItemWhenTheHelmIsShown()
    {
        Assert.Contains("Hood of the Corruptor", Prompt(Character()));
    }

    [Fact]
    public void OmitsTheHeadItemWhenTheHelmIsHidden()
    {
        Assert.DoesNotContain("Hood of the Corruptor", Prompt(Character(showHelm: false)));
    }

    [Fact]
    public void OmitsTheCloakWhenTheCloakIsHidden()
    {
        Assert.DoesNotContain("Shadow-Cloak of Dalaran", Prompt(Character(showCloak: false)));
    }

    [Fact]
    public void HidingOneSlotLeavesEveryOtherSlotListed()
    {
        // The bug would be over-correcting into a bare character; only the hidden slot goes.
        var prompt = Prompt(Character(showHelm: false, showCloak: false));
        Assert.Contains("Vestments of the Sea-Witch", prompt);
        Assert.Contains("Voidheart Mantle", prompt);
    }

    // ── directive ────────────────────────────────────────────────────────────

    [Fact]
    public void TellsTheModelTheHeadIsBareWhenTheHelmIsHidden()
    {
        Assert.Contains("wears NO headgear", Prompt(Character(showHelm: false)));
    }

    [Fact]
    public void DropsTheHairUnderHeadgearRuleWhenTheHelmIsHidden()
    {
        // That rule says never let a mohawk poke over the headgear. With the helm hidden the
        // mohawk IS the correct render, so leaving the rule in actively fights the reference.
        Assert.DoesNotContain("poking over", Prompt(Character(showHelm: false)));
    }

    [Fact]
    public void KeepsTheHairUnderHeadgearRuleWhenTheHelmIsShown()
    {
        Assert.Contains("poking over", Prompt(Character()));
    }

    // ── signature ────────────────────────────────────────────────────────────

    [Fact]
    public void HidingTheHelmInvalidatesTheCachedPortrait()
    {
        var cfg = new AppConfig.HeroShotConfig();
        Assert.NotEqual(
            HeroShotSignatureBuilder.Compute(Character(), cfg),
            HeroShotSignatureBuilder.Compute(Character(showHelm: false), cfg));
    }

    [Fact]
    public void HidingTheCloakInvalidatesTheCachedPortrait()
    {
        var cfg = new AppConfig.HeroShotConfig();
        Assert.NotEqual(
            HeroShotSignatureBuilder.Compute(Character(), cfg),
            HeroShotSignatureBuilder.Compute(Character(showCloak: false), cfg));
    }

    [Fact]
    public void ShowingBothSlotsAddsNothingToTheSignature()
    {
        // The keys are written only when a slot is hidden, so adding this feature must not
        // invalidate the portraits of every character who hides nothing — which is most of them.
        var cfg = new AppConfig.HeroShotConfig();
        var defaults = new CharacterRecord
        {
            Realm = "Dreamscythe", Account = "1", Name = "Drakuzo",
            Race = "Orc", Gender = "Female", Class = "WARLOCK",
            GearItemIds = new Dictionary<string, int> { ["head"] = 30212 },
        };
        var explicitlyShown = new CharacterRecord
        {
            Realm = "Dreamscythe", Account = "1", Name = "Drakuzo",
            Race = "Orc", Gender = "Female", Class = "WARLOCK",
            ShowHelm = true, ShowCloak = true,
            GearItemIds = new Dictionary<string, int> { ["head"] = 30212 },
        };
        Assert.Equal(
            HeroShotSignatureBuilder.Compute(defaults, cfg),
            HeroShotSignatureBuilder.Compute(explicitlyShown, cfg));
    }
}

/// <summary>
/// The addon writes the toggles as 1 = hidden. These pin the reading half, and especially the
/// back-compat case: a record scanned before the field existed, or synced from a peer on an older
/// build, has no key at all and must read as "shown" — never as "hidden", which would silently
/// strip the helmet off every character that has not been rescanned.
/// </summary>
public class HiddenSlotParsingTests : IDisposable
{
    private readonly string _path = Path.Combine(Path.GetTempPath(), $"alttracker-hidden-{Guid.NewGuid():N}.lua");

    private IReadOnlyList<CharacterRecord> Load(string charBody)
    {
        File.WriteAllText(_path, $$"""
            AltTrackerDB = {
                ["Player-1-0001"] = {
                    ["name"] = "Drakuzo", ["realm"] = "Dreamscythe", ["account"] = "1",
                    ["race"] = "Orc", ["gender"] = "Female", ["class"] = "WARLOCK", ["level"] = 70,
                    {{charBody}}
                },
            }
            """);
        return new SavedVariablesCharacterSource().LoadCharacters(_path, new RunLogger(false));
    }

    [Fact]
    public void AnAbsentToggleMeansShown()
    {
        var c = Assert.Single(Load(""));
        Assert.True(c.ShowHelm);
        Assert.True(c.ShowCloak);
    }

    [Fact]
    public void OneMeansHidden()
    {
        var c = Assert.Single(Load("""["hidehelm"] = 1, ["hidecloak"] = 1,"""));
        Assert.False(c.ShowHelm);
        Assert.False(c.ShowCloak);
    }

    [Fact]
    public void ZeroMeansShown()
    {
        var c = Assert.Single(Load("""["hidehelm"] = 0, ["hidecloak"] = 0,"""));
        Assert.True(c.ShowHelm);
        Assert.True(c.ShowCloak);
    }

    [Fact]
    public void TheTwoSlotsAreIndependent()
    {
        var c = Assert.Single(Load("""["hidehelm"] = 1, ["hidecloak"] = 0,"""));
        Assert.False(c.ShowHelm);
        Assert.True(c.ShowCloak);
    }

    [Fact]
    public void AStringValuedToggleStillParses()
    {
        // Defence in depth: DeserializeChar coerces with tonumber so a synced toggle arrives as a
        // number, but ReadInt accepts a numeric string too and nothing should hinge on which it is.
        var c = Assert.Single(Load("""["hidehelm"] = "1","""));
        Assert.False(c.ShowHelm);
    }

    public void Dispose()
    {
        if (File.Exists(_path)) File.Delete(_path);
    }
}
