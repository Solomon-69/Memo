using System.Reflection;
using System.Runtime.InteropServices;

namespace Memo;

/// <summary>
/// The app itself: tray icon, clipboard watcher, global shortcut and the popup. Lives for the whole session.
/// Left-click on the icon or the shortcut opens the popup above the tray; right-click shows the menu.
/// </summary>
internal sealed class TrayContext : ApplicationContext
{
    private readonly LaunchOptions options;
    private readonly Settings settings;
    private readonly Theme theme;
    private readonly Store store;
    private readonly PopupForm popup;
    private readonly ClipboardWatcher watcher = new();
    private readonly ClipboardCapture capture;
    private readonly HotKey hotKey;
    private readonly NotifyIcon tray;
    private readonly ContextMenuStrip menu;
    private readonly ToolStripMenuItem pauseItem, loginItem;
    private readonly System.Windows.Forms.Timer debounce = new() { Interval = 120 };
    private readonly System.Windows.Forms.Timer tickTimer = new() { Interval = 900 };
    private Icon? trayIcon;
    private SettingsForm? settingsForm;
    private IntroForm? introForm;
    private bool exiting;

    public Settings Settings => settings;
    public Store Store => store;
    public PopupForm Popup => popup;
    public HotKey Hotkey => hotKey;
    public ClipboardWatcher Watcher => watcher;
    public SettingsForm? SettingsWindow => settingsForm;
    public IntroForm? IntroWindow => introForm;

    public TrayContext(LaunchOptions options)
    {
        this.options = options;
        settings = Settings.Load();
        theme = new Theme(settings);
        store = new Store(settings);
        capture = new ClipboardCapture(settings, store);

        popup = new PopupForm(settings, theme, store);
        popup.PasteRequested += it => PasteItem(it, true);
        popup.CopyRequested += ClipboardCapture.SetClipboard;
        popup.SettingsRequested += OpenSettings;
        popup.PauseToggled += TogglePause;

        var openItem = new ToolStripMenuItem("Open Memo", null, (_, _) => popup.ShowPopup(TrayCenter()));
        openItem.Font = new Font(openItem.Font, FontStyle.Bold);
        pauseItem = new ToolStripMenuItem("Pause recording", null, (_, _) => TogglePause());
        loginItem = new ToolStripMenuItem("Open at login", null, (_, _) => Settings.SetLogin(!Settings.LoginEnabled()));
        var settingsItem = new ToolStripMenuItem("Settings...", null, (_, _) => OpenSettings());
        var quitItem = new ToolStripMenuItem("Quit Memo", null, (_, _) => ExitApp());
        menu = new ContextMenuStrip { ShowImageMargin = false, ShowCheckMargin = true };
        menu.Items.AddRange(new ToolStripItem[] { openItem, new ToolStripSeparator(), pauseItem, loginItem, settingsItem, new ToolStripSeparator(), quitItem });
        menu.Opening += (_, _) =>
        {
            pauseItem.Checked = settings.Paused;
            loginItem.Checked = Settings.LoginEnabled();
            MenuStyle.Apply(menu, theme.Palette);
        };

        tray = new NotifyIcon { Text = "Memo", ContextMenuStrip = menu, Visible = true };
        DrawTrayIcon(false);
        tray.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) popup.Toggle(TrayCenter() ?? Cursor.Position); };
        theme.TaskbarChanged += () => popup.BeginInvoke(() => DrawTrayIcon(false));
        settings.Changed += () =>
        {
            hotKey!.Register(settings.HotkeyIndex);
            DrawTrayIcon(false);
        };

        hotKey = new HotKey(() => popup.Toggle(TrayCenter() ?? Cursor.Position));
        hotKey.Register(settings.HotkeyIndex);

        debounce.Tick += async (_, _) =>
        {
            debounce.Stop();
            var item = await capture.RunAsync();
            if (item != null) FlashTick();
        };
        watcher.Updated += () => { debounce.Stop(); debounce.Start(); };
        tickTimer.Tick += (_, _) => { tickTimer.Stop(); DrawTrayIcon(false); };

        Application.Idle += StartOnce;
    }

    private void StartOnce(object? sender, EventArgs e)
    {
        Application.Idle -= StartOnce;
        popup.CreateControl();
        _ = popup.Handle;   // the window exists (hidden) so shortcuts and other launches can reach it
        if (options.SelfTestPath != null) { _ = new SelfTest(this, options).RunAsync(); return; }
        if (!settings.IntroDone && !options.NoIntro) ShowIntro();
    }

    // ---------- Windows ----------

    private void TogglePause()
    {
        settings.Paused = !settings.Paused;
        settings.Save();
        popup.Invalidate();
    }

    public void OpenSettings()
    {
        if (settingsForm == null || settingsForm.IsDisposed)
        {
            settingsForm = new SettingsForm(settings, store, theme);
            settingsForm.FormClosed += (_, _) => settingsForm = null;
        }
        popup.StayOpen = false;
        popup.HidePopup();
        settingsForm.Show();
        settingsForm.WindowState = FormWindowState.Normal;
        settingsForm.Activate();
    }

    public void ShowIntro()
    {
        introForm = new IntroForm(settings, theme);
        introForm.Finished += openPanel =>
        {
            settings.IntroDone = true;
            settings.Save();
            if (openPanel) popup.ShowPopup(TrayCenter());
        };
        introForm.Show();
        introForm.Activate();
    }

    public void OpenFromOutside() => Post(() => popup.ShowPopup(TrayCenter()));
    public void QuitFromOutside() => Post(ExitApp);

    private void Post(Action a)
    {
        try { if (!exiting && !popup.IsDisposed && popup.IsHandleCreated) popup.BeginInvoke(a); }
        catch (Exception ex) when (ex is ObjectDisposedException or InvalidOperationException) { }
    }

    // ---------- Pasting back ----------

    /// <summary>Puts the item on the clipboard, closes the panel and (unless told not to) presses Ctrl+V in the app you came from.</summary>
    public void PasteItem(ClipItem item, bool send)
    {
        var previous = popup.PreviousWindow;
        if (!popup.StayOpen) popup.HidePopup();
        ClipboardCapture.SetClipboard(item);
        store.Touch(item);
        if (send && settings.PasteDirect) _ = SendPasteAsync(previous);
    }

    private static async Task SendPasteAsync(IntPtr previous)
    {
        await Task.Delay(120);
        if (previous != IntPtr.Zero) Native.SetForegroundWindow(previous);
        await Task.Delay(150);
        Native.SendPaste();
    }

    // ---------- Tray icon ----------

    private void FlashTick()
    {
        DrawTrayIcon(true);
        tickTimer.Stop();
        tickTimer.Start();
    }

    private void DrawTrayIcon(bool tick)
    {
        var px = TraySize();
        using var bmp = new Bitmap(px, px);
        using (var g = Graphics.FromImage(bmp))
        {
            var ink = theme.TaskbarDark ? Color.White : Color.FromArgb(0x1A, 0x1A, 0x1A);
            var back = theme.TaskbarDark ? Color.FromArgb(0x20, 0x20, 0x20) : Color.FromArgb(0xF3, 0xF3, 0xF3);
            Glyph.Clipboard(g, new RectangleF(0, 0, px, px), ink, settings.Paused ? 0.45f : 1f, back, tick);
        }
        var handle = bmp.GetHicon();
        var next = (Icon)Icon.FromHandle(handle).Clone();
        Native.DestroyIcon(handle);
        tray.Icon = next;
        trayIcon?.Dispose();
        trayIcon = next;
        tray.Text = settings.Paused ? "Memo (paused)" : "Memo";
    }

    private static int TraySize()
    {
        try { return Math.Max(16, Native.GetSystemMetricsForDpi(Native.SM_CXSMICON, Native.GetDpiForSystem())); }
        catch { return SystemInformation.SmallIconSize.Width; }
    }

    /// <summary>Screen rectangle of the tray icon, or null when it is hidden in the overflow area.</summary>
    public Rectangle? TrayBounds()
    {
        if (!tray.Visible) return null;
        try
        {
            IntPtr hwnd = IntPtr.Zero;
            uint? id = null;
            foreach (var f in typeof(NotifyIcon).GetFields(BindingFlags.Instance | BindingFlags.NonPublic))
            {
                var v = f.GetValue(tray);
                if (v is NativeWindow nw) hwnd = nw.Handle;
                else if (f.Name.TrimStart('_').Equals("id", StringComparison.OrdinalIgnoreCase) && v != null) id = Convert.ToUInt32(v);
            }
            if (hwnd == IntPtr.Zero || id == null) return null;
            var nid = new Native.NOTIFYICONIDENTIFIER { cbSize = (uint)Marshal.SizeOf<Native.NOTIFYICONIDENTIFIER>(), hWnd = hwnd, uID = id.Value };
            if (Native.Shell_NotifyIconGetRect(ref nid, out var rc) != 0) return null;
            var r = Rectangle.FromLTRB(rc.Left, rc.Top, rc.Right, rc.Bottom);
            return r.Width > 0 && r.Height > 0 ? r : null;
        }
        catch (Exception ex)
        {
            Store.Log($"Tray position unknown: {ex.Message}");
            return null;
        }
    }

    public Point? TrayCenter() => TrayBounds() is { } r ? new Point(r.Left + r.Width / 2, r.Top + r.Height / 2) : null;

    private void ExitApp()
    {
        if (exiting) return;
        exiting = true;
        debounce.Dispose();
        tickTimer.Dispose();
        hotKey.Dispose();
        watcher.Dispose();
        tray.Visible = false;
        tray.Dispose();
        trayIcon?.Dispose();
        menu.Dispose();
        settingsForm?.Dispose();
        introForm?.Dispose();
        theme.Dispose();
        popup.Dispose();
        ExitThread();
    }
}

/// <summary>Tray menu colours that follow the look (WinForms menus are always light otherwise).</summary>
internal static class MenuStyle
{
    public static void Apply(ContextMenuStrip menu, Palette p)
    {
        menu.Renderer = new ToolStripProfessionalRenderer(new Colors(p)) { RoundedEdges = true };
        menu.BackColor = p.Card;
        foreach (ToolStripItem item in menu.Items) item.ForeColor = p.Text;
    }

    private sealed class Colors : ProfessionalColorTable
    {
        private readonly Palette p;
        public Colors(Palette p) { this.p = p; UseSystemColors = false; }
        public override Color ToolStripDropDownBackground => p.Card;
        public override Color MenuBorder => p.Line;
        public override Color MenuItemBorder => p.Hover;
        public override Color MenuItemSelected => p.Hover;
        public override Color MenuItemSelectedGradientBegin => p.Hover;
        public override Color MenuItemSelectedGradientEnd => p.Hover;
        public override Color ImageMarginGradientBegin => p.Card;
        public override Color ImageMarginGradientMiddle => p.Card;
        public override Color ImageMarginGradientEnd => p.Card;
        public override Color SeparatorDark => p.Line;
        public override Color SeparatorLight => p.Card;
        public override Color CheckBackground => p.Hover;
        public override Color CheckSelectedBackground => p.Hover;
        public override Color CheckPressedBackground => p.Hover;
    }
}
