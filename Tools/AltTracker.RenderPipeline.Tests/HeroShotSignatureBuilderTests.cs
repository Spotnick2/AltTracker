using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Models;
using AltTracker.RenderPipeline.Services.HeroShot;

namespace AltTracker.RenderPipeline.Tests;

/// <summary>
/// The render signature decides whether a character is re-rendered or skipped. Two of its inputs
/// were added because leaving them out produced silent staleness: the reference fingerprint (an
/// armory render that refreshed itself would never invalidate anything) and the effective
/// per-character provider (flipping one character between codex and armory kept the old portrait).
/// </summary>
public class HeroShotSignatureBuilderTests
{
    private static CharacterRecord Character(
        string account = "1", int headItemId = 12345) => new()
    {
        Realm = "Dreamscythe",
        Account = account,
        Name = "Drakuzo",
        Race = "Orc",
        Gender = "Female",
        Class = "WARLOCK",
        GearItemIds = new Dictionary<string, int> { ["head"] = headItemId, ["chest"] = 6789 },
    };

    private static AppConfig.HeroShotConfig Config() => new();

    [Fact]
    public void IsStableForIdenticalInputs()
    {
        var a = HeroShotSignatureBuilder.Compute(Character(), Config(), "fp", "codex");
        var b = HeroShotSignatureBuilder.Compute(Character(), Config(), "fp", "codex");
        Assert.Equal(a, b);
        Assert.StartsWith("hs1:", a);
    }

    [Fact]
    public void ChangesWhenTheReferenceFingerprintChanges()
    {
        // The whole point of sourcing references from the armory: a new render must re-render.
        var before = HeroShotSignatureBuilder.Compute(Character(), Config(), "fingerprint-a", "codex");
        var after = HeroShotSignatureBuilder.Compute(Character(), Config(), "fingerprint-b", "codex");
        Assert.NotEqual(before, after);
    }

    [Fact]
    public void ChangesWhenTheEffectiveProviderChanges()
    {
        // Config still says codex; only this character is overridden to armory. Hashing the global
        // default instead of the effective provider would keep the stale portrait.
        var config = Config();
        var codex = HeroShotSignatureBuilder.Compute(Character(), config, "fp", "codex");
        var armory = HeroShotSignatureBuilder.Compute(Character(), config, "fp", "armory");

        Assert.Equal("codex", config.Provider);
        Assert.NotEqual(codex, armory);
    }

    [Fact]
    public void FallsBackToTheConfiguredProviderWhenNoOverrideIsGiven()
    {
        var config = Config();
        var explicitDefault = HeroShotSignatureBuilder.Compute(Character(), config, "fp", config.Provider);
        var implied = HeroShotSignatureBuilder.Compute(Character(), config, "fp");
        Assert.Equal(explicitDefault, implied);
    }

    [Fact]
    public void ChangesWhenGearChanges()
    {
        var before = HeroShotSignatureBuilder.Compute(Character(), Config(), "fp", "codex");

        var after = HeroShotSignatureBuilder.Compute(
            Character(headItemId: 999), Config(), "fp", "codex");

        Assert.NotEqual(before, after);
    }

    [Fact]
    public void ChangesWithOutputShapeAndGenerationVersion()
    {
        var baseline = HeroShotSignatureBuilder.Compute(Character(), Config(), "fp", "codex");

        var taller = Config();
        taller.OutputHeight += 1;
        Assert.NotEqual(baseline, HeroShotSignatureBuilder.Compute(Character(), taller, "fp", "codex"));

        var bumped = Config();
        bumped.GenerationVersion = "2";
        Assert.NotEqual(baseline, HeroShotSignatureBuilder.Compute(Character(), bumped, "fp", "codex"));
    }

    [Fact]
    public void DistinguishesCharactersThatShareAName()
    {
        // Same name on two accounts must not collide - they are separate portraits.
        var one = Character(account: "1");
        var two = Character(account: "2");

        Assert.NotEqual(
            HeroShotSignatureBuilder.Compute(one, Config(), "fp", "codex"),
            HeroShotSignatureBuilder.Compute(two, Config(), "fp", "codex"));
    }

    [Fact]
    public void EmptyAndOmittedFingerprintAgree()
    {
        Assert.Equal(
            HeroShotSignatureBuilder.Compute(Character(), Config(), "", "codex"),
            HeroShotSignatureBuilder.Compute(Character(), Config(), null!, "codex"));
    }
}
