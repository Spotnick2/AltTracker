using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Models;
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

/// <summary>
/// Execute validates the configured provider eagerly, before any job reaches the chain builder.
/// Normalising in only one of those places is how an unconfigured Provider still hard-failed every
/// job while the chain unit tests passed - so these drive the real entry point.
/// </summary>
public class ProviderNormalisationTests : IDisposable
{
    private readonly string _temp =
        Path.Combine(Path.GetTempPath(), "alttracker-provider-tests", Guid.NewGuid().ToString("N"));

    public ProviderNormalisationTests() => Directory.CreateDirectory(_temp);

    public void Dispose()
    {
        try { Directory.Delete(_temp, recursive: true); } catch { /* best effort */ }
        GC.SuppressFinalize(this);
    }

    private static RenderJob Job() => new()
    {
        JobKey = "job-1",
        ManifestKey = "Dreamscythe:1:Kaleid",
        Character = new CharacterRecord { Realm = "Dreamscythe", Account = "1", Name = "Kaleid" },
        OutputBaseName = "dreamscythe_1_kaleid",
        FinalOutputPath = "unused.tga",
        FinalAddonImagePath = "unused",
        FinalAddonFilename = "x.tga",
        ExpectedStagingFileName = "x.png",
        GearHash = "sha256:0",
        Reason = "test",
    };

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("CODEX")]
    public void AnUnconfiguredProviderDoesNotFailEveryJob(string? configured)
    {
        var config = new AppConfig { RenderStagingPath = _temp };
        config.HeroShot.Provider = configured!;

        // Dry run stops before any generation, but Execute has already resolved the configured
        // provider by then - which is the step that used to throw.
        var result = new HeroShotRenderAdapter()
            .Execute([Job()], config, new CliOptions { DryRun = true }, new RunLogger(verbose: false));

        Assert.Empty(result.ErrorByJobKey);
    }

    [Fact]
    public void AGenuinelyUnknownProviderStillFailsLoudly()
    {
        var config = new AppConfig { RenderStagingPath = _temp };
        config.HeroShot.Provider = "codx";

        var result = new HeroShotRenderAdapter()
            .Execute([Job()], config, new CliOptions { DryRun = true }, new RunLogger(verbose: false));

        var error = Assert.Single(result.ErrorByJobKey);
        Assert.Contains("Unknown provider", error.Value);
    }

    [Fact]
    public void TheFactoryAndTheChainAgreeOnTheDefault()
    {
        // The two call sites must normalise identically or eager validation and per-job resolution
        // can disagree - exactly the split that caused the original defect.
        foreach (var configured in new string?[] { null, "", "   " })
        {
            Assert.Equal("codex", HeroShotRenderAdapter.NormalizeProviderName(configured));
            Assert.Equal("codex", HeroShotRenderAdapter.BuildProviderChain(configured)[0]);
        }
    }
}
