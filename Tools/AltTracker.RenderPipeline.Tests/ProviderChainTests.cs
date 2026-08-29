using AltTracker.RenderPipeline.Services;

namespace AltTracker.RenderPipeline.Tests;

/// <summary>
/// The hero shot resolves through an ordered chain: the preferred source, then the other, then
/// nothing — at which point the addon draws its identity card instead. Mirrors the same
/// AI -> armory -> card order the scene cutouts use, so both views degrade the same way.
/// </summary>
public class BuildProviderChainTests
{
    [Fact]
    public void CodexFallsBackToArmory()
        => Assert.Equal(new[] { "codex", "armory" }, HeroShotRenderAdapter.BuildProviderChain("codex"));

    [Fact]
    public void ArmoryFallsBackToCodex()
        => Assert.Equal(new[] { "armory", "codex" }, HeroShotRenderAdapter.BuildProviderChain("armory"));

    [Fact]
    public void DefaultsToCodexFirstWhenUnset()
    {
        Assert.Equal(new[] { "codex", "armory" }, HeroShotRenderAdapter.BuildProviderChain(null));
        Assert.Equal(new[] { "codex", "armory" }, HeroShotRenderAdapter.BuildProviderChain(""));
        Assert.Equal(new[] { "codex", "armory" }, HeroShotRenderAdapter.BuildProviderChain("  "));
    }

    [Fact]
    public void ManualNeverChains()
    {
        // A hand-placed import is an explicit instruction. Quietly generating something else
        // instead would hide the fact that the file was missing.
        Assert.Equal(new[] { "manual" }, HeroShotRenderAdapter.BuildProviderChain("manual"));
    }

    [Theory]
    [InlineData("CODEX")]
    [InlineData("  Armory  ")]
    public void IsCaseAndWhitespaceInsensitive(string preferred)
    {
        var chain = HeroShotRenderAdapter.BuildProviderChain(preferred);
        Assert.Equal(2, chain.Count);
        Assert.All(chain, name => Assert.Equal(name.ToLowerInvariant(), name));
    }

    [Fact]
    public void EveryChainStartsWithThePreferredSource()
    {
        foreach (var preferred in new[] { "codex", "armory", "manual" })
        {
            Assert.Equal(preferred, HeroShotRenderAdapter.BuildProviderChain(preferred)[0]);
        }
    }

    [Fact]
    public void AnUnknownNameIsLeftAloneForTheFactoryToReject()
    {
        // Chain building must not paper over a typo by appending a working provider - the run
        // should fail loudly at GetProvider instead.
        Assert.Equal(new[] { "codx" }, HeroShotRenderAdapter.BuildProviderChain("codx"));
    }
}
