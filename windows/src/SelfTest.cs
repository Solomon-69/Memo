using System.Text.Json;

namespace Memo;

/// <summary>
/// The automated Windows test, run inside the app (--selftest=PATH). It copies text, a link, a picture, files, a colour
/// and a secret onto the real clipboard, checks the history caught (or skipped) each one, tries pin, search, delete,
/// saving to disk and pasting back, then writes everything it found to PATH as JSON for ci/test.ps1 to check.
/// </summary>
internal sealed class SelfTest
{
    public const string LongText =
        "Memo self-test alpha: a longer note that wraps over several lines, so the open row shows every single word. " +
        "Second sentence about a meeting on Thursday at ten, with the agenda, the budget and the new launch plan. " +
        "Third sentence to make sure the text is long enough to need the whole row.";

    private readonly TrayContext ctx;
    private readonly LaunchOptions options;
    private readonly Dictionary<string, object?> r = new();

    public SelfTest(TrayContext ctx, LaunchOptions options)
    {
        this.ctx = ctx;
        this.options = options;
    }

    public async Task RunAsync()
    {
        try
        {
            var popup = ctx.Popup;
            r["app"] = "Memo";
            r["itemsAtStart"] = ctx.Store.Items.Count;
            r["clipboardListener"] = ctx.Watcher.Registered;
            r["hotKey"] = ctx.Hotkey.Registered;
            r["hotKeyName"] = ctx.Hotkey.Name;
            r["introDoneAtStart"] = ctx.Settings.IntroDone;

            if (options.CaptureTest) await CaptureChecks();

            if (options.TestOpen)
            {
                popup.StayOpen = true;
                popup.ShowPopup(ctx.TrayCenter());
            }
            if (options.TestExpand) { await Task.Delay(400); popup.List.SetExpanded(true); }
            if (options.TestSettings) ctx.OpenSettings();
            if (options.TestIntro) ctx.ShowIntro();
            if (Environment.GetCommandLineArgs().Contains("--test-zoomprobe"))
            {
                await ZoomProbe();
                return;
            }
            await Task.Delay(1500);

            r["popupVisible"] = popup.Visible;
            r["popupBounds"] = Box(popup.Bounds);
            r["listCount"] = popup.List.Count;
            r["settingsVisible"] = ctx.SettingsWindow is { Visible: true };
            r["settingsBounds"] = ctx.SettingsWindow is { } s ? Box(s.Bounds) : null;
            r["introVisible"] = ctx.IntroWindow is { Visible: true };
            r["introBounds"] = ctx.IntroWindow is { } i ? Box(i.Bounds) : null;
            r["tray"] = ctx.TrayBounds() is { } t ? Box(t) : null;
            r["itemsNow"] = ctx.Store.Items.Count;
        }
        catch (Exception ex)
        {
            r["error"] = ex.ToString();
            Store.Log($"Self-test failed: {ex}");
        }
        File.WriteAllText(options.SelfTestPath!, JsonSerializer.Serialize(r, new JsonSerializerOptions { WriteIndented = true }));
    }

    /// <summary>Test aid: writes the popup's size, scale, font and scroll, waits while the test presses zoom keys and scrolls with Ctrl, writes again (twice).</summary>
    private async Task ZoomProbe()
    {
        var popup = ctx.Popup;
        var path = options.SelfTestPath!;
        void Write(string name) => File.WriteAllText(path + name, JsonSerializer.Serialize(new
        {
            bounds = Box(popup.Bounds),
            dpi = popup.DeviceDpi,
            font = popup.Font.Size,
            listFont = popup.List.Font.Size,
            scroll = popup.List.ScrollY,
        }));
        async Task Gate(string go)
        {
            for (var i = 0; i < 400 && !File.Exists(path + go); i++) await Task.Delay(150);
            await Task.Delay(800);
        }
        await Task.Delay(1200);
        Write(".z0");
        await Gate(".go1"); Write(".z1");
        await Gate(".go2"); Write(".z2");
    }

    private static int[] Box(Rectangle b) => new[] { b.X, b.Y, b.Width, b.Height };

    private async Task<bool> WaitFor(Func<bool> condition, int ms = 5000)
    {
        for (var waited = 0; waited < ms; waited += 100)
        {
            if (condition()) return true;
            await Task.Delay(100);
        }
        return condition();
    }

    private static void SetText(string text) => Retry(() => Clipboard.SetDataObject(text, true, 5, 40));

    private static void Retry(Action a)
    {
        for (var n = 0; n < 8; n++)
        {
            try { a(); return; }
            catch (System.Runtime.InteropServices.ExternalException) { Thread.Sleep(60); }
        }
    }

    private static T Read<T>(Func<T> f, T fallback)
    {
        for (var n = 0; n < 8; n++)
        {
            try { return f(); }
            catch (System.Runtime.InteropServices.ExternalException) { Thread.Sleep(60); }
        }
        return fallback;
    }

    private async Task CaptureChecks()
    {
        var store = ctx.Store;
        var settings = ctx.Settings;

        SetText(LongText);
        r["textCaptured"] = await WaitFor(() => store.Items.Any(i => i.Text == LongText));
        var alpha = store.Items.FirstOrDefault(i => i.Text == LongText);

        SetText("https://example.com/page?utm_source=news&id=5&fbclid=abc123");
        r["linkCleaned"] = await WaitFor(() => store.Items.Any(i => i.Text == "https://example.com/page?id=5"));

        SetText("#1E3A8A");
        r["colourCaptured"] = await WaitFor(() => store.Items.Any(i => i.IsColor));

        using (var bmp = new Bitmap(80, 60))
        {
            using (var g = Graphics.FromImage(bmp)) g.Clear(Color.FromArgb(0x1E, 0x3A, 0x8A));
            Retry(() => Clipboard.SetImage(bmp));
        }
        r["imageCaptured"] = await WaitFor(() => store.Items.Any(i => i.Kind == Kind.Image && i.Width == 80 && i.Height == 60));
        r["imageSavedToDisk"] = Directory.Exists(Store.ImagesFolder) && Directory.GetFiles(Store.ImagesFolder, "*.png").Length >= 1;

        var tmp = Path.Combine(Path.GetTempPath(), "memo-selftest-file.txt");
        File.WriteAllText(tmp, "memo");
        var sc = new System.Collections.Specialized.StringCollection { tmp };
        Retry(() => Clipboard.SetFileDropList(sc));
        r["filesCaptured"] = await WaitFor(() => store.Items.Any(i => i.Kind == Kind.Files && i.Text.Contains("memo-selftest-file")));

        // A secret (marked the way password managers do) must be skipped.
        var secret = new DataObject();
        secret.SetText("memo secret zzz");
        secret.SetData("ExcludeClipboardContentFromMonitorProcessing", new byte[] { 1 });
        Retry(() => Clipboard.SetDataObject(secret, true, 5, 40));
        await Task.Delay(1200);
        r["secretSkipped"] = !store.Items.Any(i => i.Text.Contains("memo secret zzz"));

        // Paused: nothing is recorded.
        settings.Paused = true;
        SetText("memo paused zzz");
        await Task.Delay(1200);
        r["pausedSkipped"] = !store.Items.Any(i => i.Text.Contains("memo paused zzz"));
        settings.Paused = false;

        // Pin, search, delete.
        if (alpha != null) store.TogglePin(alpha);
        r["pinnedFirst"] = alpha != null && store.Search("").FirstOrDefault()?.Id == alpha.Id && alpha.Pinned;
        r["searchFinds"] = store.Search("alpha").Count == 1 && store.Search("qqnomatchqq").Count == 0;
        var link = store.Items.FirstOrDefault(i => i.Text == "https://example.com/page?id=5");
        var before = store.Items.Count;
        if (link != null) store.Delete(link);
        r["deleted"] = link != null && store.Items.Count == before - 1 && !store.Items.Contains(link);

        // Saved to disk and read back.
        var disk = Store.ReadFromDisk();
        r["persisted"] = disk.Count == store.Items.Count && disk.Any(i => i.Pinned && i.Text == LongText);

        // Pasting back puts the right thing on the clipboard.
        if (alpha != null)
        {
            ctx.PasteItem(alpha, false);
            await Task.Delay(300);
            r["pasteTextBack"] = Read(() => Clipboard.GetText(), "") == LongText;
        }
        var img = store.Items.FirstOrDefault(i => i.Kind == Kind.Image);
        if (img != null)
        {
            ctx.PasteItem(img, false);
            await Task.Delay(300);
            r["pasteImageBack"] = Read(() => Clipboard.ContainsImage(), false);
        }
        var files = store.Items.FirstOrDefault(i => i.Kind == Kind.Files);
        if (files != null)
        {
            ctx.PasteItem(files, false);
            await Task.Delay(300);
            r["pasteFilesBack"] = Read(() => Clipboard.ContainsFileDropList(), false);
        }
        await Task.Delay(500);
        r["noDuplicatesFromPaste"] = store.Items.Count(i => i.Text == LongText) == 1;
    }
}
