using AltTracker.RenderPipeline.Models;
using AltTracker.RenderPipeline.Services;
using AltTracker.RenderPipeline.Services.BattleNet;

namespace AltTracker.RenderPipeline.Tests;

public class PathToolsTests
{
    private static CharacterRecord Character(string realm, string account, string name) => new()
    {
        Realm = realm, Account = account, Name = name,
    };

    [Fact]
    public void ManifestKeyPreservesCasingAndOrder()
    {
        // The addon builds the same key in Lua (Roster's BuildManifestLookupKey), so this format is
        // a cross-language contract, not an internal detail.
        Assert.Equal("Dreamscythe:1:Kaleid",
            PathTools.BuildManifestKey(Character("Dreamscythe", "1", "Kaleid")));
    }

    [Fact]
    public void OutputBaseNameIsLowercasedAndSanitised()
    {
        Assert.Equal("dreamscythe_1_kaleid",
            PathTools.BuildOutputBaseName(Character("Dreamscythe", "1", "Kaleid")));
        Assert.Equal("old_blanchy_2_bob",
            PathTools.BuildOutputBaseName(Character("Old Blanchy", "2", "Bob")));
    }

    [Theory]
    // Must be addon-relative, and must not climb out of the addon folder.
    [InlineData(@"Interface\AddOns\AltTracker\Media\CharacterRenders\a.tga", true)]
    [InlineData(@"Interface\AddOns\AltTracker\Media\..\..\..\evil.tga", false)]
    [InlineData(@"C:\Windows\System32\evil.tga", false)]
    [InlineData(@"Media\CharacterRenders\a.tga", false)]
    [InlineData("", false)]
    public void ValidatesAddonImagePaths(string path, bool expected)
        => Assert.Equal(expected, PathTools.IsValidWowAddonImagePath(path));

    [Fact]
    public void GearHashTracksGearAndProfileVersion()
    {
        var character = new CharacterRecord
        {
            Realm = "Dreamscythe", Account = "1", Name = "Kaleid",
            GearItemIds = new Dictionary<string, int> { ["head"] = 111 },
        };
        var other = new CharacterRecord
        {
            Realm = "Dreamscythe", Account = "1", Name = "Kaleid",
            GearItemIds = new Dictionary<string, int> { ["head"] = 222 },
        };

        var baseline = PathTools.ComputeGearHash(character, "v1");
        Assert.StartsWith("sha256:", baseline);
        Assert.Equal(baseline, PathTools.ComputeGearHash(character, "v1"));
        Assert.NotEqual(baseline, PathTools.ComputeGearHash(other, "v1"));
        Assert.NotEqual(baseline, PathTools.ComputeGearHash(character, "v2"));
    }
}

/// <summary>
/// Cache identity must survive names that sanitise to the same token: SanitizeToken strips
/// non-ASCII, so two distinct characters can share an output base name and would otherwise share
/// one cached render.
/// </summary>
public class CacheIdTests
{
    [Fact]
    public void IsStableForTheSameCharacter()
        => Assert.Equal(
            CharacterRenderCache.CacheId("Dreamscythe:1:Kaleid", "dreamscythe_1_kaleid"),
            CharacterRenderCache.CacheId("Dreamscythe:1:Kaleid", "dreamscythe_1_kaleid"));

    [Fact]
    public void DiffersWhenTheManifestKeyDiffersDespiteAnIdenticalBaseName()
    {
        // The realistic collision: non-ASCII names sanitise down to the same base.
        var a = CharacterRenderCache.CacheId("Dreamscythe:1:Ünicode", "dreamscythe_1_nicode");
        var b = CharacterRenderCache.CacheId("Dreamscythe:2:Ünicode", "dreamscythe_1_nicode");

        Assert.NotEqual(a, b);
    }

    [Fact]
    public void StartsWithTheBaseNameSoCacheFilesStayReadable()
        => Assert.StartsWith("dreamscythe_1_kaleid-",
            CharacterRenderCache.CacheId("Dreamscythe:1:Kaleid", "dreamscythe_1_kaleid"));
}
