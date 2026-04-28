namespace AltTracker.RenderPipeline.Infrastructure;

public enum PipelineExitCode
{
    Success = 0,
    ConfigurationError = 1,
    DataError = 2,
    RenderStageFailure = 3,
    PublishError = 4,
    PartialSuccess = 5
}
