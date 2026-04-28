using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Models;

namespace AltTracker.RenderPipeline.Services;

public interface IRenderAdapter
{
    RenderAdapterResult Execute(
        IReadOnlyList<RenderJob> jobs,
        AppConfig config,
        CliOptions options,
        RunLogger logger);
}

public sealed record RenderAdapterResult(
    IReadOnlyDictionary<string, string> SourceByJobKey,
    IReadOnlyDictionary<string, string> ErrorByJobKey);
