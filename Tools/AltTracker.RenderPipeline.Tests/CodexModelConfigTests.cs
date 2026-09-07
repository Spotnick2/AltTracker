using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Models;
using AltTracker.RenderPipeline.Services.HeroShot;

namespace AltTracker.RenderPipeline.Tests;

/// <summary>
/// The model that drives codex's image_gen tool used to be smuggled in through the free-text
/// ExtraArgs string. It is now a typed field, because it is a permanent setting that materially
/// changes the portrait — a stronger driver reads the armory reference and the equipped-item list
/// noticeably better — and therefore has to invalidate cached renders when it changes.
/// </summary>
public class CodexModelConfigTests
{
    private static CharacterRecord Character() => new()
    {
        Realm = "Dreamscythe", Account = "1", Name = "Drakuzo",
        Race = "Orc", Gender = "Female", Class = "WARLOCK",
        GearItemIds = new Dictionary<string, int> { ["head"] = 30212 },
    };

    [Fact]
    public void ChangingTheDriverModelInvalidatesTheCachedPortrait()
    {
        var astra = new AppConfig.HeroShotConfig();
        astra.Codex.Model = "gpt-6-astra";
        var other = new AppConfig.HeroShotConfig();
        other.Codex.Model = "gpt-5.6-sol";

        Assert.NotEqual(
            HeroShotSignatureBuilder.Compute(Character(), astra),
            HeroShotSignatureBuilder.Compute(Character(), other));
    }

    [Fact]
    public void AnUnpinnedModelLeavesTheSignatureUntouched()
    {
        // Written only when pinned, so a config that never set it keeps its existing portraits
        // rather than re-rendering the whole roster the first time this field shipped.
        var unset = new AppConfig.HeroShotConfig();
        var blank = new AppConfig.HeroShotConfig();
        blank.Codex.Model = "   ";

        Assert.Equal(
            HeroShotSignatureBuilder.Compute(Character(), unset),
            HeroShotSignatureBuilder.Compute(Character(), blank));
    }

    [Fact]
    public void TheModelIsNotConfusedWithTheImageModel()
    {
        // HeroShot.Model is gpt-image-1, the thing that renders pixels. Codex.Model is the agent
        // driving it. They are independent, and conflating them would mean a driver swap either
        // never invalidated anything or silently rewrote the recorded image model.
        var cfg = new AppConfig.HeroShotConfig();
        Assert.Equal("gpt-image-1", cfg.Model);
        Assert.Equal("", cfg.Codex.Model);
    }

    [Fact]
    public void MediumReasoningEffortIsAccepted()
    {
        // AppConfig.Load rejects anything outside low|medium|high, and the shipped default is now
        // medium — a typo here would fail the whole run at config-load time.
        foreach (var effort in new[] { "low", "medium", "high" })
        {
            var cfg = new AppConfig.HeroShotConfig();
            cfg.Codex.ReasoningEffort = effort;
            Assert.Contains(cfg.Codex.ReasoningEffort, new[] { "low", "medium", "high" });
        }
    }
}
