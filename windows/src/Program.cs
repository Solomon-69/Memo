namespace Memo;

/// <summary>Command-line switches. --quit closes the running Memo. The rest are for the automated Windows test.</summary>
internal sealed record LaunchOptions(bool Quit, bool NoIntro, bool TestOpen, bool TestExpand, bool TestSettings, bool TestIntro, bool CaptureTest, string? SelfTestPath)
{
    public static LaunchOptions Parse(string[] args)
    {
        string? path = null;
        foreach (var a in args)
        {
            if (a.StartsWith("--selftest=", StringComparison.OrdinalIgnoreCase)) path = a["--selftest=".Length..].Trim('"');
            if (a.StartsWith("--data=", StringComparison.OrdinalIgnoreCase)) Store.Folder = a["--data=".Length..].Trim('"');
        }
        bool Has(string f) => args.Contains(f, StringComparer.OrdinalIgnoreCase);
        return new LaunchOptions(Has("--quit"), Has("--no-intro"), Has("--test-open"), Has("--test-expand"),
            Has("--test-settings"), Has("--test-intro"), Has("--capture-test"), path);
    }
}

internal static class Program
{
    private const string MutexName = @"Local\Memo.SingleInstance";
    private const string OpenEventName = @"Local\Memo.Open";
    private const string QuitEventName = @"Local\Memo.Quit";

    [STAThread]
    private static void Main(string[] args)
    {
        var options = LaunchOptions.Parse(args);

        // Single instance: a second launch just asks the running Memo to open its panel (or to quit).
        using var mutex = new Mutex(initiallyOwned: true, MutexName, out var firstInstance);
        if (!firstInstance)
        {
            try
            {
                using var signal = EventWaitHandle.OpenExisting(options.Quit ? QuitEventName : OpenEventName);
                Native.AllowSetForegroundWindow(Native.ASFW_ANY);
                signal.Set();
            }
            catch (Exception ex) { Store.Log($"Could not signal the running Memo: {ex.Message}"); }
            return;
        }
        if (options.Quit) return;

        using var openSignal = new EventWaitHandle(false, EventResetMode.AutoReset, OpenEventName);
        using var quitSignal = new EventWaitHandle(false, EventResetMode.AutoReset, QuitEventName);

        ApplicationConfiguration.Initialize();
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, e) => Store.Log($"Unhandled: {e.Exception}");
        AppDomain.CurrentDomain.UnhandledException += (_, e) => Store.Log($"Fatal: {e.ExceptionObject}");

        var context = new TrayContext(options);
        var openWait = ThreadPool.RegisterWaitForSingleObject(
            openSignal, (_, _) => context.OpenFromOutside(), null, Timeout.Infinite, executeOnlyOnce: false);
        var quitWait = ThreadPool.RegisterWaitForSingleObject(
            quitSignal, (_, _) => context.QuitFromOutside(), null, Timeout.Infinite, executeOnlyOnce: false);

        Application.Run(context);

        openWait.Unregister(null);
        quitWait.Unregister(null);
        GC.KeepAlive(mutex);
    }
}
