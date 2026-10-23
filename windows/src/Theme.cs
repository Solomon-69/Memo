using Microsoft.Win32;

namespace Memo;

/// <summary>The colours of one look (light or dark, plus the chosen app colour).</summary>
internal sealed record Palette(bool Dark, Color Back, Color Card, Color Field, Color Text, Color Sub, Color Line, Color Hover, Color Accent)
{
    public Color AccentSoft(int alpha) => Color.FromArgb(alpha, Accent);

    public static Palette Make(bool dark, int accentIndex)
    {
        var a = Settings.Accents[Math.Clamp(accentIndex, 0, Settings.Accents.Length - 1)];
        return dark
            ? new Palette(true, C(0x17181C), C(0x202228), C(0x2A2C33), C(0xF1F2F5), C(0x9A9EA8), C(0x30333A), C(0x2A2D35), a.Dark)
            : new Palette(false, C(0xF5F6F8), C(0xFFFFFF), C(0xE9EBEF), C(0x16181D), C(0x6A6F7B), C(0xDCDFE5), C(0xECEEF2), a.Light);
    }

    private static Color C(int v) => Color.FromArgb((v >> 16) & 255, (v >> 8) & 255, v & 255);
}

/// <summary>Windows light/dark (AppsUseLightTheme) plus Memo's own Appearance setting.</summary>
internal sealed class Theme : IDisposable
{
    private const string PersonalizeKey = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
    private readonly Settings settings;

    public event Action? Changed;
    public event Action? TaskbarChanged;

    public bool SystemDark { get; private set; }
    public bool TaskbarDark { get; private set; }

    public bool EffectiveDark => settings.Appearance switch { "dark" => true, "light" => false, _ => SystemDark };
    public Palette Palette => Palette.Make(EffectiveDark, settings.AccentIndex);

    public Theme(Settings settings)
    {
        this.settings = settings;
        SystemDark = ReadDark("AppsUseLightTheme", false);
        TaskbarDark = ReadDark("SystemUsesLightTheme", true);
        settings.Changed += () => Changed?.Invoke();
        SystemEvents.UserPreferenceChanged += OnPrefs;
    }

    private async void OnPrefs(object? sender, UserPreferenceChangedEventArgs e)
    {
        if (e.Category is not (UserPreferenceCategory.General or UserPreferenceCategory.Color)) return;
        Refresh();
        await Task.Delay(300);
        Refresh();
    }

    public void Refresh()
    {
        var tb = ReadDark("SystemUsesLightTheme", true);
        if (tb != TaskbarDark) { TaskbarDark = tb; TaskbarChanged?.Invoke(); }
        var d = ReadDark("AppsUseLightTheme", false);
        if (d != SystemDark) { SystemDark = d; Changed?.Invoke(); }
    }

    private static bool ReadDark(string name, bool fallback)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(PersonalizeKey);
            return key?.GetValue(name) is int light ? light == 0 : fallback;
        }
        catch { return fallback; }
    }

    public void Dispose() => SystemEvents.UserPreferenceChanged -= OnPrefs;
}
