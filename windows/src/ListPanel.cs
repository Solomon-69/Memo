using System.Drawing.Drawing2D;

namespace Memo;

/// <summary>The history list: pinned and recent rows that open to show everything, drawn by hand.</summary>
internal sealed class ListPanel : Control
{
    private sealed class Row
    {
        public ClipItem? Item;
        public string? Header;
        public int Top, Height, Body, BodyFull;
    }

    public Palette P { get; set; }
    public Store Store { get; }
    public string Query { get; set; } = "";

    public event Action<ClipItem>? Choose;
    public event Action<ClipItem>? CopyOnly;

    private readonly List<Row> rows = new();
    private readonly Dictionary<string, Bitmap> thumbs = new();
    private readonly Font title = Draw.UiFont(9.5f), small = Draw.UiFont(8f), head = Draw.UiFont(8f, FontStyle.Bold), mono = new("Consolas", 9f);
    private long selectedId = -1, expandedId = -1;
    private int scrollY, hover = -1, hoverButton = -1, innerScroll;

    public ListPanel(Store store, Palette palette)
    {
        Store = store;
        P = palette;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
        TabStop = false;
    }

    private int D(int v) => (int)Math.Round(v * DeviceDpi / 96f);
    private int RowH => D(52);
    private int Pad => D(10);

    // ---------- Model ----------

    public ClipItem? Selected => rows.FirstOrDefault(r => r.Item?.Id == selectedId)?.Item;
    public int Count => rows.Count(r => r.Item != null);
    public bool HasExpanded => expandedId != -1;
    public bool SelectedExpanded => selectedId != -1 && selectedId == expandedId;

    public void Rebuild()
    {
        var items = Store.Search(Query);
        var keep = selectedId;
        rows.Clear();
        var pinned = items.Where(i => i.Pinned).ToList();
        var recent = items.Where(i => !i.Pinned).ToList();
        if (pinned.Count > 0) rows.Add(new Row { Header = "PINNED" });
        rows.AddRange(pinned.Select(i => new Row { Item = i }));
        if (recent.Count > 0) rows.Add(new Row { Header = pinned.Count > 0 ? "RECENT" : "RECENT" });
        rows.AddRange(recent.Select(i => new Row { Item = i }));

        if (!items.Any(i => i.Id == keep)) selectedId = items.FirstOrDefault()?.Id ?? -1;
        if (!items.Any(i => i.Id == expandedId)) expandedId = -1;
        Relayout();
        Invalidate();
    }

    private void Relayout()
    {
        var y = D(4);
        var cardW = Width - 2 * Pad;
        foreach (var r in rows)
        {
            r.Top = y;
            if (r.Header != null) { r.Height = D(26); r.Body = r.BodyFull = 0; }
            else
            {
                r.BodyFull = r.Item!.Id == expandedId ? MeasureBody(r.Item, cardW - D(28)) : 0;
                r.Body = Math.Min(r.BodyFull, D(240));
                r.Height = RowH + (r.Body > 0 ? r.Body + D(12) : 0);
            }
            y += r.Height + (r.Header != null ? 0 : D(2));
        }
        total = y + D(6);
        scrollY = Math.Clamp(scrollY, 0, Math.Max(0, total - Height));
    }

    private int total;

    private int MeasureBody(ClipItem it, int width)
    {
        switch (it.Kind)
        {
            case Kind.Image:
                var t = Thumb(it);
                if (t == null) return D(40);
                var s = Math.Min(1.0, (double)width / t.Width);
                return (int)(t.Height * s);
            case Kind.Files:
                return it.Files.Length * D(20);
            default:
                if (it.IsColor) return D(84);
                var sz = TextRenderer.MeasureText(it.Text, it.IsLink ? title : title, new Size(width, 100000),
                    TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);
                return sz.Height + D(4);
        }
    }

    private Bitmap? Thumb(ClipItem it)
    {
        if (it.ImageFile == null) return null;
        if (thumbs.TryGetValue(it.ImageFile, out var b)) return b;
        var full = Store.LoadImage(it);
        if (full == null) return null;
        // Keep a copy no wider than 600 px so a big screenshot does not sit in memory at full size.
        if (full.Width > 600)
        {
            var scaled = new Bitmap(600, Math.Max(1, full.Height * 600 / full.Width));
            using (var g = Graphics.FromImage(scaled))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(full, 0, 0, scaled.Width, scaled.Height);
            }
            full.Dispose();
            full = scaled;
        }
        thumbs[it.ImageFile] = full;
        return full;
    }

    // ---------- Keyboard actions ----------

    public new void Move(int delta)
    {
        var list = rows.Where(r => r.Item != null).ToList();
        if (list.Count == 0) return;
        var i = list.FindIndex(r => r.Item!.Id == selectedId);
        i = Math.Clamp(i + delta, 0, list.Count - 1);
        selectedId = list[i].Item!.Id;
        if (expandedId != -1) { expandedId = selectedId; innerScroll = 0; }
        Relayout();
        EnsureVisible();
        Invalidate();
    }

    public void SetExpanded(bool open)
    {
        if (open && Selected != null) { expandedId = selectedId; innerScroll = 0; }
        else expandedId = -1;
        Relayout();
        EnsureVisible();
        Invalidate();
    }

    public void PinSelected() { if (Selected is { } it) Store.TogglePin(it); }
    public void DeleteSelected() { if (Selected is { } it) { Move(1); Store.Delete(it); } }
    public void ChooseSelected() { if (Selected is { } it) Choose?.Invoke(it); }

    public void ChooseNumber(int n)
    {
        var list = rows.Where(r => r.Item != null).ToList();
        if (n >= 1 && n <= list.Count) Choose?.Invoke(list[n - 1].Item!);
    }

    private void EnsureVisible()
    {
        var r = rows.FirstOrDefault(x => x.Item?.Id == selectedId);
        if (r == null) return;
        if (r.Top < scrollY) scrollY = r.Top - (rows.IndexOf(r) > 0 && rows[rows.IndexOf(r) - 1].Header != null ? D(26) : 0);
        else if (r.Top + r.Height > scrollY + Height) scrollY = r.Top + r.Height - Height + D(4);
        scrollY = Math.Clamp(scrollY, 0, Math.Max(0, total - Height));
    }

    // ---------- Mouse ----------

    private Rectangle CardRect(Row r) => new(Pad, r.Top - scrollY, Width - 2 * Pad, r.Height);

    private Rectangle ButtonRect(Row r, int index)
    {
        var c = CardRect(r);
        var w = D(26);
        return new Rectangle(c.Right - D(8) - w * (4 - index), c.Top + (RowH - w) / 2, w, w);
    }

    private int RowAt(Point p)
    {
        for (var i = 0; i < rows.Count; i++)
            if (rows[i].Item != null && CardRect(rows[i]).Contains(p)) return i;
        return -1;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var h = RowAt(e.Location);
        var b = -1;
        if (h >= 0)
            for (var k = 0; k < 4; k++)
                if (ButtonRect(rows[h], k).Contains(e.Location)) b = k;
        if (h != hover || b != hoverButton) { hover = h; hoverButton = b; Invalidate(); }
        Cursor = h >= 0 ? Cursors.Hand : Cursors.Default;
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        base.OnMouseLeave(e);
        hover = hoverButton = -1;
        Invalidate();
    }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        base.OnMouseClick(e);
        var i = RowAt(e.Location);
        if (i < 0) return;
        var row = rows[i];
        var it = row.Item!;
        selectedId = it.Id;
        if (e.Button == MouseButtons.Right) { Invalidate(); return; }
        if (ButtonRect(row, 0).Contains(e.Location)) { expandedId = expandedId == it.Id ? -1 : it.Id; innerScroll = 0; Relayout(); Invalidate(); return; }
        if (ButtonRect(row, 1).Contains(e.Location)) { Store.TogglePin(it); return; }
        if (ButtonRect(row, 2).Contains(e.Location)) { CopyOnly?.Invoke(it); return; }
        if (ButtonRect(row, 3).Contains(e.Location)) { Store.Delete(it); return; }
        if (e.Y - CardRect(row).Top < RowH) Choose?.Invoke(it);   // clicking the opened text itself does not paste
    }

    public int ScrollY => scrollY;

    protected override void OnMouseWheel(MouseEventArgs e)
    {
        base.OnMouseWheel(e);
        if ((ModifierKeys & Keys.Control) != 0) return;   // Ctrl+wheel (a trackpad pinch) never zooms or scrolls anything
        var i = RowAt(e.Location);
        if (i >= 0 && rows[i].BodyFull > rows[i].Body && e.Y - CardRect(rows[i]).Top > RowH)
        {
            innerScroll = Math.Clamp(innerScroll - e.Delta / 2, 0, rows[i].BodyFull - rows[i].Body);
        }
        else
        {
            scrollY = Math.Clamp(scrollY - e.Delta, 0, Math.Max(0, total - Height));
        }
        Invalidate();
    }

    protected override void OnResize(EventArgs e)
    {
        base.OnResize(e);
        if (rows.Count > 0) Relayout();
    }

    // ---------- Painting ----------

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.Clear(P.Back);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        if (rows.Count == 0)
        {
            var msg = Query.Trim().Length > 0 ? "Nothing matches" : "Nothing copied yet";
            Draw.Text(g, msg, title, new Rectangle(0, Height / 2 - D(20), Width, D(24)), P.Sub, TextFormatFlags.HorizontalCenter);
            if (Query.Trim().Length == 0)
                Draw.Text(g, "Copy something and it shows up here.", small, new Rectangle(0, Height / 2 + D(2), Width, D(20)), P.Sub, TextFormatFlags.HorizontalCenter);
            return;
        }
        var number = 0;
        for (var i = 0; i < rows.Count; i++)
        {
            var r = rows[i];
            var c = CardRect(r);
            if (r.Item != null) number++;
            if (c.Bottom < 0 || c.Top > Height) continue;
            if (r.Header != null)
            {
                Draw.Text(g, r.Header, head, new Rectangle(c.X + D(6), c.Y + D(6), c.Width, D(16)), P.Sub);
                continue;
            }
            PaintRow(g, r, c, i, number);
        }
    }

    private void PaintRow(Graphics g, Row r, Rectangle c, int index, int number)
    {
        var it = r.Item!;
        var selected = it.Id == selectedId;
        var open = it.Id == expandedId;
        var hot = index == hover;
        if (open || selected || hot)
            Draw.FillRound(g, open ? P.Card : selected ? P.AccentSoft(P.Dark ? 60 : 36) : P.Hover, c, D(10));
        if (open) Draw.StrokeRound(g, P.Line, c, D(10));
        if (it.Pinned) Draw.FillRound(g, P.Accent, new RectangleF(c.X + D(2), c.Y + D(12), D(3), RowH - D(24)), D(2));

        // icon tile
        var tile = new Rectangle(c.X + D(12), c.Y + (RowH - D(30)) / 2, D(30), D(30));
        if (it.IsColor && TryColor(it.Text, out var swatch))
            Draw.FillRound(g, swatch, tile, D(8));
        else
        {
            Draw.FillRound(g, P.AccentSoft(P.Dark ? 70 : 38), tile, D(8));
            Draw.Glyph(g, it.Kind == Kind.Image ? "" : it.Kind == Kind.Files ? "" : it.IsLink ? "" : "", 11f, tile, P.Accent);
        }

        var showButtons = hot || selected;
        var right = c.Right - D(10) - (showButtons ? D(26) * 4 : D(44));
        var textX = tile.Right + D(10);
        Draw.Text(g, it.Title.Length == 0 ? "(blank)" : it.Title, title, new Rectangle(textX, c.Y + D(8), right - textX, D(20)), P.Text);
        var sub = (it.App.Length > 0 ? it.App + "  -  " : "") + Draw.Ago(it.Time);
        Draw.Text(g, sub, small, new Rectangle(textX, c.Y + D(28), right - textX, D(16)), P.Sub);

        if (showButtons)
        {
            string[] glyphs = { open ? "" : "", "", "", "" };
            for (var k = 0; k < 4; k++)
            {
                var b = ButtonRect(r, k);
                if (hover == index && hoverButton == k) Draw.FillRound(g, P.Line, b, D(7));
                var col = k == 1 && it.Pinned ? P.Accent : P.Sub;
                Draw.Glyph(g, glyphs[k], 10f, b, col);
            }
        }
        else if (number <= 9)
            Draw.Text(g, $"Ctrl {number}", small, new Rectangle(c.Right - D(52), c.Y + (RowH - D(16)) / 2, D(42), D(16)), P.Sub, TextFormatFlags.Right);

        if (r.Body > 0) PaintBody(g, r, c, it);
    }

    private void PaintBody(Graphics g, Row r, Rectangle c, ClipItem it)
    {
        var body = new Rectangle(c.X + D(14), c.Y + RowH, c.Width - D(28), r.Body);
        var old = g.Clip;
        g.SetClip(body);
        switch (it.Kind)
        {
            case Kind.Image:
                var t = Thumb(it);
                if (t != null)
                {
                    var s = Math.Min(1.0, (double)body.Width / t.Width);
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.DrawImage(t, body.X, body.Y - innerScroll, (int)(t.Width * s), (int)(t.Height * s));
                }
                break;
            case Kind.Files:
                for (var k = 0; k < it.Files.Length; k++)
                    Draw.Text(g, it.Files[k], small, new Rectangle(body.X, body.Y + k * D(20) - innerScroll, body.Width, D(20)), P.Text);
                break;
            default:
                if (it.IsColor && TryColor(it.Text, out var col))
                {
                    Draw.FillRound(g, col, new Rectangle(body.X, body.Y, body.Width, D(56)), D(10));
                    Draw.Text(g, it.Text.Trim().ToUpperInvariant(), mono, new Rectangle(body.X, body.Y + D(60), body.Width, D(22)), P.Text);
                }
                else
                    TextRenderer.DrawText(g, it.Text, title, new Rectangle(body.X, body.Y - innerScroll, body.Width, 100000), P.Text,
                        TextFormatFlags.WordBreak | TextFormatFlags.NoPadding | TextFormatFlags.Top);
                break;
        }
        g.Clip = old;
    }

    private static bool TryColor(string text, out Color color)
    {
        color = Color.Gray;
        try
        {
            var t = text.Trim().TrimStart('#');
            if (t.Length == 3) t = string.Concat(t.Select(ch => $"{ch}{ch}"));
            if (t.Length == 8) t = t[..6];
            if (t.Length != 6) return false;
            color = Color.FromArgb(Convert.ToInt32(t[..2], 16), Convert.ToInt32(t[2..4], 16), Convert.ToInt32(t[4..6], 16));
            return true;
        }
        catch { return false; }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            foreach (var b in thumbs.Values) b.Dispose();
            title.Dispose(); small.Dispose(); head.Dispose(); mono.Dispose();
        }
        base.Dispose(disposing);
    }
}
