namespace Memo;

/// <summary>Memo's settings: Look, General, History and Privacy. Every change is saved the moment it is made.</summary>
internal sealed class SettingsForm : Form
{
    private readonly Settings settings;
    private readonly Store store;
    private readonly Theme theme;
    private readonly Panel scroll = new() { Dock = DockStyle.Fill, AutoScroll = true };
    private readonly SwatchStrip swatches;
    private readonly Label usage = new() { AutoSize = true };
    private readonly ListBox ignored = new();
    private readonly List<Label> heads = new(), subs = new();
    private int y;
    private bool loading = true;

    public SettingsForm(Settings settings, Store store, Theme theme)
    {
        this.settings = settings;
        this.store = store;
        this.theme = theme;

        Text = "Memo Settings";
        AutoScaleMode = AutoScaleMode.Dpi;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ShowInTaskbar = true;
        Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath ?? "") ?? Icon;
        Font = Draw.UiFont(9.5f);
        ClientSize = new Size(Dp(440), Dp(620));
        Controls.Add(scroll);
        y = Dp(16);

        // ---- Look ----
        Head("Look");
        Sub("App colour");
        swatches = new SwatchStrip(settings, theme) { Location = new Point(Dp(20), y), Size = new Size(Dp(390), Dp(34)) };
        swatches.Picked += i => { settings.AccentIndex = i; settings.Save(); };
        scroll.Controls.Add(swatches);
        y += Dp(46);
        Sub("Appearance");
        var look = Combo(new[] { "Follow Windows", "Light", "Dark" }, settings.Appearance == "light" ? 1 : settings.Appearance == "dark" ? 2 : 0);
        look.SelectedIndexChanged += (_, _) => { if (loading) return; settings.Appearance = new[] { "system", "light", "dark" }[look.SelectedIndex]; settings.Save(); };

        // ---- General ----
        Head("General");
        Sub("Shortcut that opens Memo");
        var keys = Combo(Settings.Hotkeys.Select(h => h.Name).ToArray(), settings.HotkeyIndex);
        keys.SelectedIndexChanged += (_, _) => { if (loading) return; settings.HotkeyIndex = keys.SelectedIndex; settings.Save(); };
        Check("Open at login", Settings.LoginEnabled(), v => Settings.SetLogin(v));
        Check("Paste straight into the app", settings.PasteDirect, v => { settings.PasteDirect = v; settings.Save(); });

        // ---- History ----
        Head("History");
        Number("Keep for (days)", settings.KeepDays, 1, 365, v => settings.KeepDays = v);
        Number("Most items to keep", settings.MaxItems, 10, 5000, v => settings.MaxItems = v);
        Number("Pictures size limit (MB)", settings.MaxMegabytes, 10, 5000, v => settings.MaxMegabytes = v);
        usage.Location = new Point(Dp(20), y);
        scroll.Controls.Add(usage);
        y += Dp(28);
        var clear = Btn("Clear history (pinned items stay)", Dp(250));
        clear.Click += (_, _) => { store.ClearUnpinned(); RefreshUsage(); };

        // ---- Privacy ----
        Head("Privacy");
        Check("Skip passwords and secrets", settings.SkipSecrets, v => { settings.SkipSecrets = v; settings.Save(); });
        Check("Clean tracking bits from links", settings.CleanLinks, v => { settings.CleanLinks = v; settings.Save(); });
        Check("Pause recording", settings.Paused, v => { settings.Paused = v; settings.Save(); });
        Sub("Apps to ignore (program name, for example KeePass)");
        ignored.Location = new Point(Dp(20), y);
        ignored.Size = new Size(Dp(390), Dp(96));
        ignored.BorderStyle = BorderStyle.FixedSingle;
        scroll.Controls.Add(ignored);
        FillIgnored();
        y += Dp(104);
        var name = new TextBox { Location = new Point(Dp(20), y), Width = Dp(190), PlaceholderText = "Program name" };
        scroll.Controls.Add(name);
        var add = Btn("Add", Dp(80), Dp(218));
        add.Click += (_, _) =>
        {
            var n = name.Text.Trim();
            if (n.Length == 0 || settings.IgnoredApps.Contains(n, StringComparer.OrdinalIgnoreCase)) return;
            settings.IgnoredApps.Add(n);
            settings.Save();
            name.Text = "";
            FillIgnored();
        };
        var remove = Btn("Remove", Dp(90), Dp(306));
        remove.Click += (_, _) =>
        {
            if (ignored.SelectedItem is string s) { settings.IgnoredApps.RemoveAll(a => a == s); settings.Save(); FillIgnored(); }
        };
        y += Dp(46);
        var foot = new Label { Text = "Memo keeps your history only on this PC and sends nothing anywhere.", AutoSize = false, Location = new Point(Dp(20), y), Size = new Size(Dp(390), Dp(40)) };
        subs.Add(foot);
        scroll.Controls.Add(foot);

        RefreshUsage();
        ApplyColors();
        theme.Changed += OnThemeChanged;
        FormClosed += (_, _) => theme.Changed -= OnThemeChanged;
        loading = false;
    }

    private int Dp(int v) => (int)Math.Round(v * DeviceDpi / 96f);

    private void OnThemeChanged() { if (!IsDisposed) BeginInvoke(ApplyColors); }

    // ---------- Building blocks ----------

    private void Head(string text)
    {
        y += Dp(10);
        var l = new Label { Text = text, AutoSize = true, Location = new Point(Dp(16), y), Font = Draw.UiFont(12f, FontStyle.Bold) };
        heads.Add(l);
        scroll.Controls.Add(l);
        y += Dp(32);
    }

    private void Sub(string text)
    {
        var l = new Label { Text = text, AutoSize = true, Location = new Point(Dp(20), y) };
        subs.Add(l);
        scroll.Controls.Add(l);
        y += Dp(24);
    }

    private ComboBox Combo(string[] items, int selected)
    {
        var c = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, FlatStyle = FlatStyle.Flat, Location = new Point(Dp(20), y), Width = Dp(250) };
        c.Items.AddRange(items);
        c.SelectedIndex = Math.Clamp(selected, 0, items.Length - 1);
        scroll.Controls.Add(c);
        y += Dp(38);
        return c;
    }

    private void Check(string text, bool value, Action<bool> set)
    {
        var c = new CheckBox { Text = text, Checked = value, AutoSize = true, Location = new Point(Dp(20), y) };
        c.CheckedChanged += (_, _) => { if (!loading) set(c.Checked); };
        scroll.Controls.Add(c);
        y += Dp(30);
    }

    private void Number(string text, int value, int min, int max, Action<int> set)
    {
        var l = new Label { Text = text, AutoSize = false, Location = new Point(Dp(20), y + Dp(3)), Size = new Size(Dp(230), Dp(24)) };
        subs.Add(l);
        scroll.Controls.Add(l);
        var n = new NumericUpDown { Minimum = min, Maximum = max, Value = Math.Clamp(value, min, max), Location = new Point(Dp(260), y), Width = Dp(90), BorderStyle = BorderStyle.FixedSingle };
        n.ValueChanged += (_, _) => { if (loading) return; set((int)n.Value); settings.Save(); RefreshUsage(); };
        scroll.Controls.Add(n);
        y += Dp(34);
    }

    private Button Btn(string text, int width, int x = 20)
    {
        var b = new Button { Text = text, FlatStyle = FlatStyle.Flat, Location = new Point(x == 20 ? Dp(20) : x, y), Size = new Size(width, Dp(30)) };
        b.FlatAppearance.BorderSize = 1;
        scroll.Controls.Add(b);
        return b;
    }

    private void FillIgnored()
    {
        ignored.Items.Clear();
        foreach (var a in settings.IgnoredApps) ignored.Items.Add(a);
    }

    private void RefreshUsage()
    {
        usage.Text = $"Using {store.DiskBytes() / 1048576.0:0.0} MB for {store.Items.Count} items";
    }

    private void ApplyColors()
    {
        var p = theme.Palette;
        BackColor = p.Back;
        scroll.BackColor = p.Back;
        ForeColor = p.Text;
        if (IsHandleCreated) Native.SetDwmInt(Handle, Native.DWMWA_USE_IMMERSIVE_DARK_MODE, p.Dark ? 1 : 0);
        foreach (var l in heads) { l.ForeColor = p.Text; l.BackColor = p.Back; }
        foreach (var l in subs) { l.ForeColor = p.Sub; l.BackColor = p.Back; }
        usage.ForeColor = p.Sub; usage.BackColor = p.Back;
        foreach (Control c in scroll.Controls)
        {
            switch (c)
            {
                case CheckBox cb: cb.ForeColor = p.Text; cb.BackColor = p.Back; break;
                case ComboBox co: co.ForeColor = p.Text; co.BackColor = p.Field; break;
                case NumericUpDown nu: nu.ForeColor = p.Text; nu.BackColor = p.Field; break;
                case TextBox tb: tb.ForeColor = p.Text; tb.BackColor = p.Field; break;
                case ListBox lb: lb.ForeColor = p.Text; lb.BackColor = p.Field; break;
                case Button bt: bt.ForeColor = p.Text; bt.BackColor = p.Card; bt.FlatAppearance.BorderColor = p.Line; break;
            }
        }
        swatches.Invalidate();
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        Native.SetDwmInt(Handle, Native.DWMWA_USE_IMMERSIVE_DARK_MODE, theme.Palette.Dark ? 1 : 0);
    }

    /// <summary>The eight app colours as round swatches; the chosen one has a ring.</summary>
    private sealed class SwatchStrip : Control
    {
        private readonly Settings settings;
        private readonly Theme theme;
        public event Action<int>? Picked;

        public SwatchStrip(Settings settings, Theme theme)
        {
            this.settings = settings;
            this.theme = theme;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
            Cursor = Cursors.Hand;
        }

        private int Slot => Width / Settings.Accents.Length;

        protected override void OnPaint(PaintEventArgs e)
        {
            var p = theme.Palette;
            var g = e.Graphics;
            g.Clear(p.Back);
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            var d = Math.Min(Height - 8, Slot - 8);
            for (var i = 0; i < Settings.Accents.Length; i++)
            {
                var c = theme.EffectiveDark ? Settings.Accents[i].Dark : Settings.Accents[i].Light;
                var r = new RectangleF(i * Slot + (Slot - d) / 2f, (Height - d) / 2f, d, d);
                using var b = new SolidBrush(c);
                g.FillEllipse(b, r);
                if (i == settings.AccentIndex)
                {
                    r.Inflate(4, 4);
                    using var pen = new Pen(p.Text, 2f);
                    g.DrawEllipse(pen, r);
                }
            }
        }

        protected override void OnMouseClick(MouseEventArgs e)
        {
            base.OnMouseClick(e);
            var i = e.X / Math.Max(1, Slot);
            if (i >= 0 && i < Settings.Accents.Length) { Picked?.Invoke(i); Invalidate(); }
        }
    }
}
