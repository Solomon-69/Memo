namespace Memo;

/// <summary>
/// The panel that opens above the tray icon: search box, the history list and a few buttons.
/// Hides itself as soon as it loses focus (unless StayOpen, which the automated test uses).
/// </summary>
internal sealed class PopupForm : Form
{
    private readonly Settings settings;
    private readonly Theme theme;
    private readonly Store store;
    private readonly TextBox search = new();
    private readonly ListPanel list;
    private readonly Font ui = Draw.UiFont(9.5f), small = Draw.UiFont(8f);
    private Palette P;
    private Rectangle searchRect, gearRect, pauseRect;
    private int hotButton = -1;

    public bool StayOpen { get; set; }
    public IntPtr PreviousWindow { get; private set; }

    public event Action<ClipItem>? PasteRequested;
    public event Action<ClipItem>? CopyRequested;
    public event Action? SettingsRequested;
    public event Action? PauseToggled;

    public ListPanel List => list;
    public TextBox SearchBox => search;

    public PopupForm(Settings settings, Theme theme, Store store)
    {
        this.settings = settings;
        this.theme = theme;
        this.store = store;
        P = theme.Palette;

        Text = "Memo";
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        KeyPreview = true;
        DoubleBuffered = true;
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(Dp(380), Dp(540));

        search.BorderStyle = BorderStyle.None;
        search.Font = ui;
        search.PlaceholderText = "Search";
        search.TextChanged += (_, _) => { list.Query = search.Text; list.Rebuild(); };
        Controls.Add(search);

        list = new ListPanel(store, P);
        list.Choose += it => PasteRequested?.Invoke(it);
        list.CopyOnly += it => CopyRequested?.Invoke(it);
        Controls.Add(list);

        store.Changed += () => { if (IsHandleCreated) BeginInvoke(() => { list.Rebuild(); Invalidate(); }); };
        theme.Changed += ApplyTheme;
        ApplyTheme();
        DoLayout();
        list.Rebuild();
    }

    private int Dp(int v) => (int)Math.Round(v * DeviceDpi / 96f);

    private void DoLayout()
    {
        var w = ClientSize.Width;
        var pad = Dp(12);
        gearRect = new Rectangle(w - pad - Dp(34), Dp(10), Dp(34), Dp(34));
        pauseRect = new Rectangle(gearRect.X - Dp(38), Dp(10), Dp(34), Dp(34));
        searchRect = new Rectangle(pad, Dp(10), pauseRect.X - pad - Dp(6), Dp(34));
        search.SetBounds(searchRect.X + Dp(34), searchRect.Y + (searchRect.Height - search.Height) / 2, searchRect.Width - Dp(44), search.Height);
        list.SetBounds(0, Dp(56), w, ClientSize.Height - Dp(56) - Dp(30));
    }

    private void ApplyTheme()
    {
        P = theme.Palette;
        BackColor = P.Back;
        search.BackColor = P.Field;
        search.ForeColor = P.Text;
        list.P = P;
        if (IsHandleCreated)
        {
            Native.SetDwmInt(Handle, Native.DWMWA_USE_IMMERSIVE_DARK_MODE, P.Dark ? 1 : 0);
        }
        list.Invalidate();
        Invalidate();
    }

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ClassStyle |= 0x20000;   // CS_DROPSHADOW
            cp.ExStyle |= 0x80;         // WS_EX_TOOLWINDOW: never in Alt+Tab or the taskbar
            return cp;
        }
    }

    protected override bool ShowWithoutActivation => false;

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        Native.SetDwmInt(Handle, Native.DWMWA_WINDOW_CORNER_PREFERENCE, Native.DWMWCP_ROUND);
        Native.SetDwmInt(Handle, Native.DWMWA_USE_IMMERSIVE_DARK_MODE, P.Dark ? 1 : 0);
    }

    // ---------- Showing ----------

    /// <summary>Opens the panel so its bottom edge sits just above the anchor (the tray icon).</summary>
    public void ShowPopup(Point? anchor)
    {
        if (!Visible) PreviousWindow = Native.GetForegroundWindow();
        search.Text = "";
        list.Rebuild();
        list.SetExpanded(false);
        Place(anchor ?? DefaultAnchor());
        Show();
        Native.AllowSetForegroundWindow(Native.ASFW_ANY);
        Native.SetForegroundWindow(Handle);
        Activate();
        search.Focus();
    }

    public void HidePopup() { if (Visible) Hide(); }

    public void Toggle(Point? anchor)
    {
        if (Visible) Hide(); else ShowPopup(anchor);
    }

    private static Point DefaultAnchor()
    {
        var work = Screen.PrimaryScreen?.WorkingArea ?? new Rectangle(0, 0, 1280, 720);
        return new Point(work.Right - 1, work.Bottom - 1);
    }

    private void Place(Point anchor)
    {
        var work = Screen.FromPoint(anchor).WorkingArea;
        var w = Width;
        var h = Height;
        var gap = Dp(8);
        int x, y;
        switch (Native.TaskbarEdge())
        {
            case Native.ABE_LEFT: x = work.Left + gap; y = anchor.Y - h / 2; break;
            case Native.ABE_RIGHT: x = work.Right - w - gap; y = anchor.Y - h / 2; break;
            case Native.ABE_TOP: x = anchor.X - w / 2; y = work.Top + gap; break;
            default: x = anchor.X - w / 2; y = work.Bottom - h - gap; break;
        }
        x = Math.Clamp(x, work.Left + gap, Math.Max(work.Left + gap, work.Right - w - gap));
        y = Math.Clamp(y, work.Top + gap, Math.Max(work.Top + gap, work.Bottom - h - gap));
        Location = new Point(x, y);
    }

    protected override void OnDeactivate(EventArgs e)
    {
        base.OnDeactivate(e);
        if (!StayOpen && Visible) Hide();
    }

    // ---------- Keys ----------

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        var emptyOrEnd = search.TextLength == 0 || search.SelectionStart == search.TextLength;
        var emptyOrStart = search.TextLength == 0 || search.SelectionStart == 0;
        switch (keyData)
        {
            case Keys.Down: list.Move(1); return true;
            case Keys.Up: list.Move(-1); return true;
            case Keys.Enter:
            case Keys.Alt | Keys.Enter:
            case Keys.Alt | Keys.Shift | Keys.Enter: list.ChooseSelected(); return true;
            case Keys.Right when emptyOrEnd: list.SetExpanded(true); return true;
            case Keys.Left when emptyOrStart && list.HasExpanded: list.SetExpanded(false); return true;
            case Keys.Space when search.TextLength == 0: list.SetExpanded(!list.SelectedExpanded); return true;
            case Keys.Control | Keys.P: list.PinSelected(); return true;
            case Keys.Control | Keys.Delete: list.DeleteSelected(); return true;
            case Keys.Delete when search.TextLength == 0: list.DeleteSelected(); return true;
            case Keys.Escape:
                if (list.HasExpanded) list.SetExpanded(false);
                else if (search.TextLength > 0) search.Text = "";
                else Hide();
                return true;
        }
        if ((keyData & Keys.Control) != 0 && (keyData & ~Keys.Control) >= Keys.D1 && (keyData & ~Keys.Control) <= Keys.D9)
        {
            list.ChooseNumber((int)(keyData & ~Keys.Control) - (int)Keys.D0);
            return true;
        }
        return base.ProcessCmdKey(ref msg, keyData);
    }

    // ---------- Painting and header buttons ----------

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        var g = e.Graphics;
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        Draw.FillRound(g, P.Field, searchRect, Dp(10));
        Draw.Glyph(g, "", 10f, new Rectangle(searchRect.X + Dp(6), searchRect.Y, Dp(26), searchRect.Height), P.Sub);

        DrawButton(g, pauseRect, settings.Paused ? "" : "", 0, settings.Paused ? P.Accent : P.Sub);
        DrawButton(g, gearRect, "", 1, P.Sub);

        var foot = new Rectangle(Dp(16), ClientSize.Height - Dp(28), ClientSize.Width - Dp(32), Dp(24));
        var hint = settings.Paused ? "Recording is paused" : "Enter to paste  -  Ctrl+P pin  -  Right to open";
        Draw.Text(g, hint, small, foot, settings.Paused ? P.Accent : P.Sub);
        Draw.Text(g, $"{store.Items.Count} items", small, foot, P.Sub, TextFormatFlags.Right);
        using var pen = new Pen(P.Line);
        g.DrawLine(pen, 0, Dp(55), ClientSize.Width, Dp(55));
        g.DrawLine(pen, 0, ClientSize.Height - Dp(30), ClientSize.Width, ClientSize.Height - Dp(30));
    }

    private void DrawButton(Graphics g, Rectangle r, string glyph, int index, Color color)
    {
        if (hotButton == index) Draw.FillRound(g, P.Field, r, Dp(10));
        Draw.Glyph(g, glyph, 11f, r, color);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var h = pauseRect.Contains(e.Location) ? 0 : gearRect.Contains(e.Location) ? 1 : -1;
        if (h != hotButton) { hotButton = h; Invalidate(); }
    }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        base.OnMouseClick(e);
        if (pauseRect.Contains(e.Location)) PauseToggled?.Invoke();
        else if (gearRect.Contains(e.Location)) SettingsRequested?.Invoke();
    }

    /// <summary>Hit rectangles for the automated test: where the gear button sits on screen.</summary>
    public Rectangle GearOnScreen => RectangleToScreen(gearRect);

    protected override void Dispose(bool disposing)
    {
        if (disposing) { ui.Dispose(); small.Dispose(); }
        base.Dispose(disposing);
    }
}
