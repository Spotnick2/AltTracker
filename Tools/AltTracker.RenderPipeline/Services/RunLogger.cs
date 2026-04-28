namespace AltTracker.RenderPipeline.Services;

public sealed class RunLogger
{
    private readonly bool _verbose;

    public RunLogger(bool verbose)
    {
        _verbose = verbose;
    }

    public void Info(string message) => Write("INFO", message);
    public void Warn(string message) => Write("WARN", message);
    public void Error(string message) => Write("ERROR", message);

    public void Verbose(string message)
    {
        if (_verbose)
        {
            Write("VERBOSE", message);
        }
    }

    private static void Write(string level, string message)
    {
        Console.WriteLine($"{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss} [{level}] {message}");
    }
}
