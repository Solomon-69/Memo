namespace Memo;

/// <summary>The welcome window shown once after installing: what Memo is, pasting, and the shortcut. Three pages, skippable.</summary>
internal sealed class IntroForm : Form
{
    private const int Pages = 3;
    private readonly Settings settings;
    private readonly Theme theme;
    private readonly Button next = new(), skip = new();
    private readonly CheckBox pasteBox = new();
    private readonly System.Windows.Forms.Timer slide = new() { Interval = 15 };
    private readonly Font big = Draw.UiFont(21f, FontStyle.Bold), body = Draw.UiFont(10.5f), mid = Draw.UiFont(10.5f, FontStyle.Bold), small = Draw.UiFont(9f);
    private int page;
    private double progress = 1;   // 0 to 1, how far the new page has slid in
    private DateTime slideStart;

    public event Action<bool>? Finished;

    public IntroForm(Settings settings, Theme theme)
    {
        this.settings = settings;
        this.theme = theme;
        Text = "Welcome to Memo";
        AutoScaleMode = AutoScaleMode.Dpi;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        DoubleBuffered = true;
        Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath ?? "") ?? Icon;
        ClientSize = new Size(Dp(440), Dp(500));

        next.FlatStyle = FlatStyle.Flat;
        next.FlatAppearance.BorderSize = 0;
        next.Size = new Size(Dp(150), Dp(38));
        next.Location = new Point(ClientSize.Width - Dp(28) - next.Width, ClientSize.Height - Dp(62));
        next.Click += (_, _) => Advance();
        skip.Text = "Skip";
        skip.FlatStyle = FlatStyle.Flat;
        skip.FlatAppearance.BorderSize = 0;
        skip.Size = new Size(Dp(80), Dp(38));
        skip.Location = new Point(Dp(24), ClientSize.Height - Dp(62));
        skip.Click += (_, _) => Finish(false);
        pasteBox.Text = "Paste for me";
        pasteBox.AutoSize = true;
        pasteBox.Checked = settings.PasteDirect;
        pasteBox.Location = new Point(Dp(60), Dp(290));
        pasteBox.CheckedChanged += (_, _) => { settings.PasteDirect = pasteBox.Checked; settings.Save(); };
        Controls.AddRange(new Control[] { next, skip, pasteBox });

        slide.Tick += (_, _) =>
        {
            var t = Math.Min(1.0, (DateTime.UtcNow - slideStart).TotalMilliseconds / 260.0);
            progress = 1 - Math.Pow(1 - t, 3);
            if (t >= 1) slide.Stop();
            Invalidate();
        };
        FormClosed += (_, _) => { slide.Dispose(); big.Dispose(); body.Dispose(); mid.Dispose(); small.Dispose(); };
        theme.Changed += OnTheme;
        FormClosed += (_, _) => theme.Changed -= OnTheme;
        Apply();
    }

    private int Dp(int v) => (int)Math.Round(v * DeviceDpi / 96f);

    private void OnTheme() { if (!IsDisposed) BeginInvoke(Apply); }

    private void Apply()
    {
        var p = theme.Palette;
        BackColor = p.Back;
        next.BackColor = p.Accent;
        next.ForeColor = Color.White;
        next.Text = page < Pages - 1 ? "Continue" : "Open Memo";
        skip.BackColor = p.Back;
        skip.ForeColor = p.Sub;
        pasteBox.BackColor = p.Back;
        pasteBox.ForeColor = p.Text;
        pasteBox.Visible = page == 1;
        if (IsHandleCreated) Native.SetDwmInt(Handle, Native.DWMWA_USE_IMMERSIVE_DARK_MODE, p.Dark ? 1 : 0);
        Invalidate();
    }

    private void Advance()
    {
        if (page >= Pages - 1) { Finish(true); return; }
        page++;
        progress = 0;
        slideStart = DateTime.UtcNow;
        slide.Start();
        Apply();
    }

    private void Finish(bool open)
    {
        Finished?.Invoke(open);
        Close();
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        Native.SetDwmInt(Handle, Native.DWMWA_USE_IMMERSIVE_DARK_MODE, theme.Palette.Dark ? 1 : 0);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        var p = theme.Palette;
        var g = e.Graphics;
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        // a soft wash of the app colour behind the top
        using (var wash = new System.Drawing.Drawing2D.LinearGradientBrush(new Rectangle(0, 0, ClientSize.Width, Dp(220)), p.AccentSoft(p.Dark ? 70 : 46), Color.FromArgb(0, p.Accent), 90f))
            g.FillRectangle(wash, 0, 0, ClientSize.Width, Dp(220));

        var dx = (int)((1 - progress) * Dp(60));
        var w = ClientSize.Width;
        switch (page)
        {
            case 0:
                Tile(g, p, dx);
                Center(g, "Welcome to Memo", big, p.Text, Dp(150), dx);
                Center(g, "Everything you copy, one shortcut away.", body, p.Sub, Dp(196), dx);
                Bullet(g, p, "Remembers text, pictures and files you copy", Dp(262), dx);
                Bullet(g, p, "Find anything in a few letters", Dp(300), dx);
                Bullet(g, p, "Stays on this PC, nothing is sent anywhere", Dp(338), dx);
                break;
            case 1:
                Center(g, "Paste straight into apps", big, p.Text, Dp(70), dx);
                Wrapped(g, "Pick an item and Memo types it where your cursor is. On Windows this needs no special permission.", body, p.Sub, new Rectangle(Dp(50) + dx, Dp(130), w - Dp(100), Dp(100)));
                Wrapped(g, "Turn it off and Memo only copies, then you press Ctrl+V yourself.", small, p.Sub, new Rectangle(Dp(60) + dx, Dp(330), w - Dp(120), Dp(50)));
                Center(g, "You can change this any time in Memo's Settings.", small, p.Sub, Dp(400), dx);
                break;
            default:
                Tile(g, p, dx);
                Center(g, "You're all set", big, p.Text, Dp(150), dx);
                Center(g, "Copy something, then press", body, p.Sub, Dp(200), dx);
                KeyCaps(g, p, settings.Hotkey.Name.Split('+'), Dp(250), dx);
                Center(g, "or click the clipboard icon near the clock.", body, p.Sub, Dp(320), dx);
                break;
        }
        // page dots
        for (var i = 0; i < Pages; i++)
        {
            var c = i == page ? p.Accent : p.Line;
            using var b = new SolidBrush(c);
            g.FillEllipse(b, w / 2 - Dp(24) + i * Dp(18), ClientSize.Height - Dp(48), Dp(8), Dp(8));
        }
    }

    private void Tile(Graphics g, Palette p, int dx)
    {
        var r = new Rectangle(ClientSize.Width / 2 - Dp(44) + dx, Dp(40), Dp(88), Dp(88));
        Draw.FillRound(g, p.Accent, r, Dp(22));
        Glyph.Clipboard(g, new RectangleF(r.X + Dp(14), r.Y + Dp(14), Dp(60), Dp(60)), Color.White);
    }

    private void Center(Graphics g, string text, Font f, Color c, int top, int dx) =>
        TextRenderer.DrawText(g, text, f, new Rectangle(dx, top, ClientSize.Width, Dp(40)), c,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);

    private static void Wrapped(Graphics g, string text, Font f, Color c, Rectangle r) =>
        TextRenderer.DrawText(g, text, f, r, c, TextFormatFlags.WordBreak | TextFormatFlags.NoPadding | TextFormatFlags.Top);

    private void Bullet(Graphics g, Palette p, string text, int top, int dx)
    {
        using var b = new SolidBrush(p.Accent);
        g.FillEllipse(b, Dp(60) + dx, top + Dp(8), Dp(8), Dp(8));
        TextRenderer.DrawText(g, text, body, new Rectangle(Dp(80) + dx, top, ClientSize.Width - Dp(110), Dp(24)), p.Text,
            TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter);
    }

    private void KeyCaps(Graphics g, Palette p, string[] keys, int top, int dx)
    {
        var widths = keys.Select(k => Math.Max(Dp(48), TextRenderer.MeasureText(k, mid).Width + Dp(26))).ToArray();
        var total = widths.Sum() + (keys.Length - 1) * Dp(10);
        var x = (ClientSize.Width - total) / 2 + dx;
        for (var i = 0; i < keys.Length; i++)
        {
            var r = new Rectangle(x, top, widths[i], Dp(46));
            Draw.FillRound(g, p.Card, r, Dp(10));
            Draw.StrokeRound(g, p.Line, r, Dp(10));
            TextRenderer.DrawText(g, keys[i], mid, r, p.Text, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            x += widths[i] + Dp(10);
        }
    }
}
