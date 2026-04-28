namespace AltTracker.RenderPipeline.Models;

public sealed class RenderJob
{
    public required string JobKey { get; init; }
    public required string ManifestKey { get; init; }
    public required CharacterRecord Character { get; init; }
    public required string OutputBaseName { get; init; }
    public required string FinalOutputPath { get; init; }
    public required string FinalAddonImagePath { get; init; }
    public required string FinalAddonFilename { get; init; }
    public required string ExpectedStagingFileName { get; init; }
    public required string GearHash { get; init; }
    public required string Reason { get; init; }
}
