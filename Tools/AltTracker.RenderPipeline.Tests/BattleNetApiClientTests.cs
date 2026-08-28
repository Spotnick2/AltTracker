using AltTracker.RenderPipeline.Services.BattleNet;

namespace AltTracker.RenderPipeline.Tests;

/// <summary>
/// The full-body render URL is derived from the avatar URL whenever character-media does not list
/// a main-raw asset. The derivation is deliberately strict — a wrong guess here would send the
/// pipeline off to fetch an arbitrary URL — so these pin down both what it accepts and what it
/// refuses.
/// </summary>
public class TryDeriveMainRawUrlTests
{
    // Verified live against the real CDN: both of these return 200.
    private const string RealAvatar =
        "https://render.worldofwarcraft.com/classicann-us/character/dreamscythe/110/45832558-avatar.jpg";
    private const string RealMainRaw =
        "https://render.worldofwarcraft.com/classicann-us/character/dreamscythe/110/45832558-main-raw.png";

    [Fact]
    public void DerivesTheKnownGoodUrl()
    {
        Assert.True(BattleNetApiClient.TryDeriveMainRawUrl(RealAvatar, out var url));
        Assert.Equal(RealMainRaw, url);
    }

    [Fact]
    public void RecomputesTheShardRatherThanTrustingThePath()
    {
        // 45832558 % 256 == 110. Feed a deliberately wrong shard and the derivation must correct it
        // rather than propagate a path that would 404.
        const string wrongShard =
            "https://render.worldofwarcraft.com/classicann-us/character/dreamscythe/999/45832558-avatar.jpg";

        Assert.True(BattleNetApiClient.TryDeriveMainRawUrl(wrongShard, out var url));
        Assert.Equal(RealMainRaw, url);
    }

    [Theory]
    // Not the render CDN — must never be followed.
    [InlineData("https://evil.example.com/classicann-us/character/dreamscythe/110/45832558-avatar.jpg")]
    // Plain HTTP is refused even on the right host.
    [InlineData("http://render.worldofwarcraft.com/classicann-us/character/dreamscythe/110/45832558-avatar.jpg")]
    // Filename does not match the expected shape.
    [InlineData("https://render.worldofwarcraft.com/classicann-us/character/dreamscythe/110/45832558-inset.jpg")]
    [InlineData("https://render.worldofwarcraft.com/classicann-us/character/dreamscythe/110/avatar.jpg")]
    [InlineData("https://render.worldofwarcraft.com/classicann-us/character/dreamscythe/110/45832558-avatar.png")]
    // Too few path segments to carry a shard.
    [InlineData("https://render.worldofwarcraft.com/45832558-avatar.jpg")]
    // Right domain, wrong service - the host check must not degrade to a bare domain match.
    [InlineData("https://www.worldofwarcraft.com/classicann-us/character/dreamscythe/110/45832558-avatar.jpg")]
    [InlineData("https://worldofwarcraft.com/classicann-us/character/dreamscythe/110/45832558-avatar.jpg")]
    [InlineData("https://renderer.worldofwarcraft.com/classicann-us/character/dreamscythe/110/45832558-avatar.jpg")]
    // A lookalike domain that merely ends with the expected text.
    [InlineData("https://render.worldofwarcraft.com.evil.test/classicann-us/character/dreamscythe/110/45832558-avatar.jpg")]
    // Not a URL at all.
    [InlineData("45832558-avatar.jpg")]
    [InlineData("")]
    public void RefusesAnythingUnexpected(string avatarUrl)
    {
        Assert.False(BattleNetApiClient.TryDeriveMainRawUrl(avatarUrl, out var url));
        Assert.Null(url);
    }

    [Fact]
    public void AcceptsARegionalRenderSubdomain()
    {
        // Blizzard's own docs use this form, so region-prefixed CDN hosts must be accepted.
        const string regional =
            "https://render-us.worldofwarcraft.com/classicann-us/character/dreamscythe/110/45832558-avatar.jpg";

        Assert.True(BattleNetApiClient.TryDeriveMainRawUrl(regional, out var url));
        Assert.Equal(
            "https://render-us.worldofwarcraft.com/classicann-us/character/dreamscythe/110/45832558-main-raw.png",
            url);
    }
}

/// <summary>
/// Realm slugs normally come from the realm index; this is the fallback for realms the index does
/// not return.
/// </summary>
public class NormalizeSlugTests
{
    [Theory]
    [InlineData("Dreamscythe", "dreamscythe")]
    [InlineData("Old Blanchy", "old-blanchy")]
    [InlineData("PROGWOW US1 GMSS 1", "progwow-us1-gmss-1")]
    [InlineData("Al'Akir", "al-akir")]
    [InlineData("  Nightslayer  ", "nightslayer")]
    public void NormalizesRealmNames(string input, string expected)
        => Assert.Equal(expected, BattleNetApiClient.NormalizeSlug(input));

    [Fact]
    public void CollapsesRunsAndTrimsSeparators()
    {
        // Consecutive punctuation must not produce empty segments, and the slug must not start or
        // end with a separator.
        Assert.Equal("a-b", BattleNetApiClient.NormalizeSlug("  a -- b  "));
        Assert.Equal("realm", BattleNetApiClient.NormalizeSlug("'Realm'"));
    }
}
