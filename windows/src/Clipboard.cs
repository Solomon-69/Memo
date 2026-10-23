using System.Collections.Specialized;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Memo;

/// <summary>Hears every clipboard change (AddClipboardFormatListener) on a hidden message window.</summary>
internal sealed class ClipboardWatcher : NativeWindow, IDisposable
{
    public event Action? Updated;
    public bool Registered { get; }

    public ClipboardWatcher()
    {
        CreateHandle(new CreateParams { Parent = new IntPtr(-3) });   // HWND_MESSAGE
        Registered = Native.AddClipboardFormatListener(Handle);
        if (!Registered) Store.Log("Could not listen to the clipboard.");
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == Native.WM_CLIPBOARDUPDATE) Updated?.Invoke();
        base.WndProc(ref m);
    }

    public void Dispose()
    {
        if (Handle != IntPtr.Zero)
        {
            Native.RemoveClipboardFormatListener(Handle);
            DestroyHandle();
        }
    }
}

/// <summary>Turns a clipboard change into a history item: text, picture or files, minus secrets and ignored apps.</summary>
internal sealed class ClipboardCapture
{
    private readonly Settings settings;
    private readonly Store store;

    public ClipboardCapture(Settings settings, Store store)
    {
        this.settings = settings;
        this.store = store;
    }

    /// <summary>The item that was saved, or null when nothing was kept.</summary>
    public async Task<ClipItem?> RunAsync()
    {
        if (settings.Paused) return null;
        IDataObject? data = null;
        for (var attempt = 0; attempt < 8 && data == null; attempt++)
        {
            try { data = Clipboard.GetDataObject(); }
            catch (ExternalException) { await Task.Delay(60); }
        }
        if (data == null) return null;

        try
        {
            if (settings.SkipSecrets && IsSecret(data)) return null;
            var app = OwnerName();
            if (app.Length > 0 && settings.IgnoredApps.Any(a => string.Equals(a, app, StringComparison.OrdinalIgnoreCase))) return null;
            if (app == "Memo") app = "";   // our own paste: keep the app name it already has

            if (data.GetDataPresent(DataFormats.FileDrop) && data.GetData(DataFormats.FileDrop) is string[] files && files.Length > 0)
                return store.AddFiles(files, app);
            if (data.GetDataPresent(DataFormats.UnicodeText) && data.GetData(DataFormats.UnicodeText) is string text)
                return store.AddText(text, app);
            if (data.GetDataPresent(DataFormats.Bitmap) || data.GetDataPresent(DataFormats.Dib))
            {
                using var image = Clipboard.GetImage();
                if (image != null) return store.AddImage(image, app);
            }
        }
        catch (Exception ex) when (ex is ExternalException or InvalidOperationException or OutOfMemoryException or ArgumentException)
        {
            Store.Log($"Could not read the clipboard: {ex.Message}");
        }
        return null;
    }

    /// <summary>Password managers and Windows itself mark secret copies with these formats.</summary>
    private static bool IsSecret(IDataObject data)
    {
        if (data.GetDataPresent("ExcludeClipboardContentFromMonitorProcessing")) return true;
        try
        {
            if (data.GetDataPresent("CanIncludeInClipboardHistory") && data.GetData("CanIncludeInClipboardHistory") is MemoryStream ms)
            {
                var b = ms.ToArray();
                if (b.Length >= 4 && BitConverter.ToInt32(b, 0) == 0) return true;
            }
        }
        catch { }
        return false;
    }

    private static string OwnerName()
    {
        try
        {
            var hwnd = Native.GetClipboardOwner();
            if (hwnd == IntPtr.Zero) return "";
            Native.GetWindowThreadProcessId(hwnd, out var pid);
            if (pid == 0) return "";
            using var p = Process.GetProcessById((int)pid);
            return p.ProcessName;
        }
        catch { return ""; }
    }

    // ---------- Putting an item back on the clipboard ----------

    public static void SetClipboard(ClipItem item)
    {
        for (var attempt = 0; attempt < 8; attempt++)
        {
            try
            {
                switch (item.Kind)
                {
                    case Kind.Image:
                        using (var bmp = Store.LoadImage(item)) { if (bmp != null) Clipboard.SetImage(bmp); }
                        break;
                    case Kind.Files:
                        var sc = new StringCollection();
                        sc.AddRange(item.Files);
                        Clipboard.SetFileDropList(sc);
                        break;
                    default:
                        Clipboard.SetDataObject(item.Text, true, 5, 40);
                        break;
                }
                return;
            }
            catch (ExternalException) { Thread.Sleep(50); }
        }
        Store.Log("Could not put the item on the clipboard.");
    }
}

/// <summary>The global shortcut that opens Memo, registered on a hidden message window.</summary>
internal sealed class HotKey : NativeWindow, IDisposable
{
    private const int Id = 0x4D45;   // "ME"
    private readonly Action onPress;

    public bool Registered { get; private set; }
    public string Name { get; private set; } = "";

    public HotKey(Action onPress)
    {
        this.onPress = onPress;
        CreateHandle(new CreateParams { Parent = new IntPtr(-3) });
    }

    /// <summary>Registers the chosen shortcut; if another app owns it, tries the others so Memo is never unreachable.</summary>
    public void Register(int preferred)
    {
        if (Registered) Native.UnregisterHotKey(Handle, Id);
        Registered = false;
        var order = new[] { preferred }.Concat(Enumerable.Range(0, Settings.Hotkeys.Length).Where(i => i != preferred));
        foreach (var i in order)
        {
            var c = Settings.Hotkeys[i];
            if (Native.RegisterHotKey(Handle, Id, c.Mods | Native.MOD_NOREPEAT, c.Vk))
            {
                Registered = true;
                Name = c.Name;
                if (i != preferred) Store.Log($"{Settings.Hotkeys[preferred].Name} is taken by another app; using {c.Name}.");
                return;
            }
        }
        Store.Log("No shortcut could be registered; open Memo from the tray icon.");
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == Native.WM_HOTKEY && m.WParam.ToInt32() == Id) onPress();
        base.WndProc(ref m);
    }

    public void Dispose()
    {
        if (Handle != IntPtr.Zero)
        {
            Native.UnregisterHotKey(Handle, Id);
            DestroyHandle();
        }
    }
}
