using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Models;
using AltTracker.RenderPipeline.Services;

namespace AltTracker.RenderPipeline.Tests;

/// <summary>
/// The planner decides what gets rendered at all. It runs BEFORE the render adapter and drops
/// unchanged characters, which is why a render that changed only on Battle.net needs an explicit
/// planning reason — without one the refresh would appear to work and silently never fire.
/// </summary>
public class RenderPlannerTests : IDisposable
{
    private readonly string _outputDir =
        Path.Combine(Path.GetTempPath(), "alttracker-planner-tests", Guid.NewGuid().ToString("N"));

    private readonly RunLogger _logger = new(verbose: false);

    public RenderPlannerTests() => Directory.CreateDirectory(_outputDir);

    public void Dispose()
    {
        try { Directory.Delete(_outputDir, recursive: true); } catch { /* best effort */ }
        GC.SuppressFinalize(this);
    }

    private AppConfig Config() => new()
    {
        OutputRenderDirectory = _outputDir,
        WowAddonImageRoot = @"Interface\AddOns\AltTracker\Media\CharacterRenders",
        MaxAgeDays = 30,
    };

    private static CharacterRecord Kaleid(int headItemId = 111) => new()
    {
        Realm = "Dreamscythe", Account = "1", Name = "Kaleid",
        GearItemIds = new Dictionary<string, int> { ["head"] = headItemId },
    };

    /// <summary>An "already rendered, nothing changed" state: manifest entry + the .tga on disk.</summary>
    private Dictionary<string, ManifestEntry> SettledManifest(CharacterRecord character, AppConfig config)
    {
        var baseName = PathTools.BuildOutputBaseName(character);
        File.WriteAllBytes(Path.Combine(_outputDir, baseName + ".tga"), [0x00]);

        return new Dictionary<string, ManifestEntry>(StringComparer.OrdinalIgnoreCase)
        {
            [PathTools.BuildManifestKey(character)] = new ManifestEntry
            {
                Image = PathTools.CombineWowPath(config.WowAddonImageRoot, baseName + ".tga"),
                GeneratedAt = DateTimeOffset.UtcNow.ToString("O"),
                GearHash = PathTools.ComputeGearHash(character, config.RenderProfileVersion),
                Mode = "heroshot",
            },
        };
    }

    [Fact]
    public void SkipsACharacterWithNothingToDo()
    {
        var config = Config();
        var character = Kaleid();

        var plan = new RenderPlanner().BuildPlan(
            [character], SettledManifest(character, config), config, new CliOptions(), _logger);

        Assert.Empty(plan.Jobs);
        Assert.Equal(1, plan.SkippedCount);
    }

    [Fact]
    public void ArmoryUpdateCreatesAJobForAnOtherwiseUnchangedCharacter()
    {
        // The planner hole. Local data is identical, the .tga exists and the gear hash matches, so
        // every other reason is silent - only the armory signal can produce this job. Without it a
        // player logging out in new gear would never get a new portrait.
        var config = Config();
        var character = Kaleid();
        var manifestKey = PathTools.BuildManifestKey(character);

        var plan = new RenderPlanner().BuildPlan(
            [character], SettledManifest(character, config), config, new CliOptions(), _logger,
            new HashSet<string>(StringComparer.OrdinalIgnoreCase) { manifestKey });

        var job = Assert.Single(plan.Jobs);
        Assert.Equal(manifestKey, job.ManifestKey);
        Assert.Contains("armory-render-updated", job.Reason);
    }

    [Fact]
    public void ArmoryUpdateForADifferentCharacterDoesNotQueueThisOne()
    {
        var config = Config();
        var character = Kaleid();

        var plan = new RenderPlanner().BuildPlan(
            [character], SettledManifest(character, config), config, new CliOptions(), _logger,
            new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Dreamscythe:9:SomeoneElse" });

        Assert.Empty(plan.Jobs);
    }

    [Fact]
    public void MissingOutputImageQueuesARender()
    {
        var config = Config();
        var character = Kaleid();
        var manifest = SettledManifest(character, config);
        File.Delete(Path.Combine(_outputDir, PathTools.BuildOutputBaseName(character) + ".tga"));

        var plan = new RenderPlanner().BuildPlan(
            [character], manifest, config, new CliOptions(), _logger);

        Assert.Contains("missing-output-image", Assert.Single(plan.Jobs).Reason);
    }

    [Fact]
    public void ChangedGearQueuesARender()
    {
        var config = Config();
        var manifest = SettledManifest(Kaleid(), config);

        // Same character, different head item -> different gear hash.
        var plan = new RenderPlanner().BuildPlan(
            [Kaleid(headItemId: 999)], manifest, config, new CliOptions(), _logger);

        Assert.Contains("gear-hash-changed", Assert.Single(plan.Jobs).Reason);
    }

    [Fact]
    public void AbsentFromTheManifestQueuesARender()
    {
        var config = Config();
        var plan = new RenderPlanner().BuildPlan(
            [Kaleid()], new Dictionary<string, ManifestEntry>(), config, new CliOptions(), _logger);

        Assert.Contains("missing-manifest-entry", Assert.Single(plan.Jobs).Reason);
    }

    [Fact]
    public void ForceAllQueuesEvenSettledCharacters()
    {
        var config = Config();
        var character = Kaleid();

        var plan = new RenderPlanner().BuildPlan(
            [character], SettledManifest(character, config), config,
            new CliOptions { ForceAll = true }, _logger);

        Assert.Contains("force-all", Assert.Single(plan.Jobs).Reason);
    }
}

/// <summary>
/// The --character filter is shared with the --refresh-armory preflight, so a single-character run
/// does not revalidate every character against Battle.net.
/// </summary>
public class MatchesFilterTests
{
    private static readonly CharacterRecord Kaleid = new()
    {
        Realm = "Dreamscythe", Account = "1", Name = "Kaleid",
    };

    [Fact]
    public void NoFilterMatchesEveryone()
        => Assert.True(RenderPlanner.MatchesFilter(Kaleid, new CliOptions()));

    [Theory]
    [InlineData("Dreamscythe:1:Kaleid")]   // manifest key
    [InlineData("dreamscythe_1_kaleid")]   // output base name
    [InlineData("Kaleid")]                 // bare character name
    public void MatchesAnyAcceptedForm(string filter)
    {
        var options = new CliOptions();
        options.CharacterFilters.Add(filter);
        Assert.True(RenderPlanner.MatchesFilter(Kaleid, options));
    }

    [Fact]
    public void DoesNotMatchAnUnrelatedFilter()
    {
        var options = new CliOptions();
        options.CharacterFilters.Add("Drakuzo");
        Assert.False(RenderPlanner.MatchesFilter(Kaleid, options));
    }
}
