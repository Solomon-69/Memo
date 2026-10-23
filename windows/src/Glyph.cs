using System.Drawing.Drawing2D;

namespace Memo;

/// <summary>The Memo mark: a clipboard with three lines, drawn to any size (tray icon, welcome window).</summary>
internal static class Glyph
{
    public static void Clipboard(Graphics g, RectangleF box, Color color, float alpha = 1f, Color? tickBack = null, bool tick = false)
    {
        var c = Color.FromArgb((int)(255 * alpha), color);
        var s = Math.Min(box.Width, box.Height) / 100f;
        float X(float v) => box.X + (box.Width - 100 * s) / 2f + v * s;
        float Y(float v) => box.Y + (box.Height - 100 * s) / 2f + v * s;
        var old = g.SmoothingMode;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        using (var pen = new Pen(c, Math.Max(1.4f, 8f * s)) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round })
        using (var brush = new SolidBrush(c))
        {
            using (var board = Draw.Round(new RectangleF(X(20), Y(14), 60 * s, 80 * s), 11 * s)) g.DrawPath(pen, board);
            using (var clip = Draw.Round(new RectangleF(X(36), Y(5), 28 * s, 20 * s), 7 * s)) g.FillPath(brush, clip);
            g.DrawLine(pen, X(36), Y(47), X(64), Y(47));
            g.DrawLine(pen, X(36), Y(61), X(64), Y(61));
            g.DrawLine(pen, X(36), Y(75), X(54), Y(75));
            if (tick)
            {
                g.FillEllipse(brush, X(52), Y(52), 46 * s, 46 * s);
                using var tp = new Pen(tickBack ?? Color.Black, Math.Max(1.4f, 8f * s)) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round };
                g.DrawLines(tp, new[] { new PointF(X(63), Y(76)), new PointF(X(71), Y(84)), new PointF(X(84), Y(66)) });
            }
        }
        g.SmoothingMode = old;
    }
}
