using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Models;
using AltTracker.RenderPipeline.Services.BattleNet;

namespace AltTracker.RenderPipeline.Tests;

/// <summary>
/// Blizzard does not generate character renders below level 10, so those characters are skipped
/// before any request is made. Confirmed against live data: Karuzo (1), Bankphisto (2) and
/// Cowruzo (7) all 404, while Kaleid (61), Drakuzo (70) and Kalinelle (70) all resolve.
/// </summary>
public class ArmoryLevelGateTests
{
    private const int DefaultMinimum = 10;

    private static CharacterRecord At(int level) => new()
    {
        Realm = "Dreamscythe", Account = "1", Name = "Someone", Level = level,
    };

    [Theory]
    [InlineData(1)]    // Karuzo
    [InlineData(2)]    // Bankphisto
    [InlineData(7)]    // Cowruzo
    [InlineData(9)]    // last level with no render
    public void SkipsCharactersBelowTheThreshold(int level)
        => Assert.True(ArmoryReferenceResolver.IsBelowRenderLevel(At(level), DefaultMinimum));

    [Theory]
    [InlineData(10)]   // first level Blizzard renders
    [InlineData(61)]   // Kaleid
    [InlineData(70)]   // Drakuzo, Kalinelle
    public void LooksUpCharactersAtOrAboveTheThreshold(int level)
        => Assert.False(ArmoryReferenceResolver.IsBelowRenderLevel(At(level), DefaultMinimum));

    [Fact]
    public void AnUnknownLevelIsLookedUpRatherThanSkipped()
    {
        // Level 0 means the addon never recorded one. Skipping on missing data would silently
        // deny a max-level character its render; a wasted request is the cheaper mistake.
        Assert.False(ArmoryReferenceResolver.IsBelowRenderLevel(At(0), DefaultMinimum));
    }

    [Fact]
    public void ThresholdIsConfigurable()
    {
        // The rule is Blizzard's policy, not ours, so the number is config rather than a constant.
        Assert.True(ArmoryReferenceResolver.IsBelowRenderLevel(At(15), minimumLevel: 20));
        Assert.False(ArmoryReferenceResolver.IsBelowRenderLevel(At(15), minimumLevel: 10));
    }

    [Fact]
    public void ZeroThresholdLooksUpEveryone()
        => Assert.False(ArmoryReferenceResolver.IsBelowRenderLevel(At(1), minimumLevel: 0));

    [Fact]
    public void DefaultConfigMatchesBlizzardsPolicy()
        => Assert.Equal(10, new AppConfig.BattleNetConfig().MinimumCharacterLevel);
}
