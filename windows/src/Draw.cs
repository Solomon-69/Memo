using System.Drawing.Drawing2D;

namespace Memo;

/// <summary>Small drawing helpers shared by the popup, settings and welcome windows.</summary>
internal static class Draw
{
    public const string IconFont = "Segoe MDL2 Assets";

    public static GraphicsPath Round(RectangleF r, float radius)
    {
        var p = new GraphicsPath();
        var d = Math.Min(radius * 2, Math.Min(r.Width, r.Height));
        if (d <= 0) { p.AddRectangle(r); return p; }
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    public static void FillRound(Graphics g, Color c, RectangleF r, float radius)
    {
        using var p = Round(r, radius);
        using var b = new SolidBrush(c);
        g.FillPath(b, p);
    }

    public static void StrokeRound(Graphics g, Color c, RectangleF r, float radius, float width = 1f)
    {
        using var p = Round(r, radius);
        using var pen = new Pen(c, width);
        g.DrawPath(pen, p);
    }

    public static void Text(Graphics g, string s, Font f, Rectangle r, Color c, TextFormatFlags extra = 0) =>
        TextRenderer.DrawText(g, s, f, r, c,
            TextFormatFlags.NoPadding | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter | extra);

    /// <summary>A glyph from Segoe MDL2 Assets, centred in a rectangle.</summary>
    public static void Glyph(Graphics g, string glyph, float size, Rectangle r, Color c)
    {
        using var f = new Font(IconFont, size, FontStyle.Regular, GraphicsUnit.Point);
        TextRenderer.DrawText(g, glyph, f, r, c,
            TextFormatFlags.NoPadding | TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
    }

    public static string Ago(DateTime utc)
    {
        var s = (DateTime.UtcNow - utc).TotalSeconds;
        if (s < 45) return "now";
        if (s < 3600) return $"{(int)(s / 60) + 1}m ago";
        if (s < 86400) return $"{(int)(s / 3600)}h ago";
        return $"{(int)(s / 86400)}d ago";
    }

    public static Font UiFont(float pt, FontStyle style = FontStyle.Regular) => new("Segoe UI", pt, style, GraphicsUnit.Point);
}
