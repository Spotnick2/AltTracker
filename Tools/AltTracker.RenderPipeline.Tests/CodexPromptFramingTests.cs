using AltTracker.RenderPipeline.Services.HeroShot;

namespace AltTracker.RenderPipeline.Tests;

/// <summary>
/// The publish step resizes-to-fill and center-crops the generated image to the configured render
/// spec, so the prompt has to pin the aspect ratio. It previously said only "portrait orientation
/// (taller than wide)": the model picked its own ratio each run, and a frame taller than the target
/// lost its top and bottom to that crop — observed live as a portrait shipped without its head
/// ornament or feet. These tests hold the ratio wording in the prompt.
/// </summary>
public class CodexPromptFramingTests
{
    private const int TargetWidth = 1024;
    private const int TargetHeight = 1792;

    private static string Build(int width = TargetWidth, int height = TargetHeight) =>
        CodexImagegenProvider.BuildPrompt(
            corePrompt: "A heroic female Orc Warlock.",
            refTempPath: null,
            webSearchEnabled: false,
            width: width,
            height: height);

    [Fact]
    public void StatesTheExactTargetPixelSize()
    {
        Assert.Contains("1024x1792 pixels", Build());
    }

    [Fact]
    public void StatesTheAspectRatioInLowestTerms()
    {
        // 1024:1792 reduces to 4:7 — the model reads a small ratio far more reliably than raw pixels.
        Assert.Contains("aspect ratio 4:7", Build());
    }

    [Fact]
    public void WarnsThatATallerFrameLosesTheHeadAndFeet()
    {
        var prompt = Build();
        Assert.Contains("CENTER-CROPPED", prompt);
        Assert.Contains("TALLER", prompt);
        Assert.Contains("decapitates", prompt);
    }

    [Fact]
    public void TellsTheModelToErrWiderRatherThanTaller()
    {
        // The asymmetry is the whole point: surplus width is cropped off the sides harmlessly,
        // surplus height is cropped off the head and feet.
        Assert.Contains("WIDER", Build());
    }

    [Theory]
    [InlineData(1024, 1536, "2:3")]
    [InlineData(512, 896, "4:7")]
    [InlineData(1000, 1000, "1:1")]
    public void ReducesAnyTargetToLowestTerms(int width, int height, string expected)
    {
        Assert.Contains($"aspect ratio {expected}", Build(width, height));
    }

    [Theory]
    [InlineData(0, 1792)]
    [InlineData(1024, 0)]
    [InlineData(-1, -1)]
    public void FallsBackToTheGenericWordingWhenDimensionsAreUnusable(int width, int height)
    {
        // A zero/negative target means the caller has no spec to enforce; emitting "0x0 pixels" or
        // dividing by zero would be worse than the old generic line.
        var prompt = Build(width, height);
        Assert.Contains("portrait orientation (taller than wide)", prompt);
        Assert.DoesNotContain("CENTER-CROPPED", prompt);
    }

    [Fact]
    public void StillAsksForExactlyOneImageAndAnArtifactPath()
    {
        // Guards the harvest contract: attribution is fail-closed on exactly one new file, and the
        // reported path is what disambiguates it.
        var prompt = Build();
        Assert.Contains("EXACTLY ONE image", prompt);
        Assert.Contains("ARTIFACT_PATH:", prompt);
    }
}
