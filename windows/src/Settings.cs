using System.Text.Json;
using Microsoft.Win32;

namespace Memo;

internal sealed record HotkeyChoice(string Name, uint Mods, uint Vk);

/// <summary>Everything the user can change, saved as settings.json in %APPDATA%\Memo.</summary>
internal sealed class Settings
{
    public static readonly HotkeyChoice[] Hotkeys =
    {
        new("Ctrl+Shift+V", Native.MOD_CONTROL | Native.MOD_SHIFT, 0x56),
        new("Ctrl+Alt+V", Native.MOD_CONTROL | Native.MOD_ALT, 0x56),
        new("Win+Shift+V", Native.MOD_WIN | Native.MOD_SHIFT, 0x56),
        new("Ctrl+Alt+M", Native.MOD_CONTROL | Native.MOD_ALT, 0x4D),
    };

    public static readonly (string Name, Color Light, Color Dark)[] Accents =
    {
        ("Navy", Rgb(0x1E3A8A), Rgb(0x5876D6)),
        ("Ocean", Rgb(0x0A6CD6), Rgb(0x4FA3FF)),
        ("Teal", Rgb(0x0E9F8E), Rgb(0x2DD4BF)),
        ("Violet", Rgb(0x6D4BD8), Rgb(0xA48BFF)),
        ("Rose", Rgb(0xC72C5B), Rgb(0xFF6F93)),
        ("Ember", Rgb(0xD06A00), Rgb(0xFF9F0A)),
        ("Moss", Rgb(0x2F7D3A), Rgb(0x5FD06E)),
        ("Graphite", Rgb(0x3F4652), Rgb(0xB4BCC8)),
    };

    private static Color Rgb(int v) => Color.FromArgb((v >> 16) & 255, (v >> 8) & 255, v & 255);

    public int AccentIndex { get; set; }
    public string Appearance { get; set; } = "system";   // system, light, dark
    public int HotkeyIndex { get; set; }
    public bool PasteDirect { get; set; } = true;
    public int KeepDays { get; set; } = 30;
    public int MaxItems { get; set; } = 500;
    public int MaxMegabytes { get; set; } = 200;
    public bool SkipSecrets { get; set; } = true;
    public bool CleanLinks { get; set; } = true;
    public bool Paused { get; set; }
    public bool IntroDone { get; set; }
    public List<string> IgnoredApps { get; set; } = new() { "1Password", "Bitwarden", "KeePass", "KeePassXC", "LastPass", "Dashlane", "Enpass" };

    public event Action? Changed;

    public HotkeyChoice Hotkey => Hotkeys[Math.Clamp(HotkeyIndex, 0, Hotkeys.Length - 1)];

    private static string PathFile => System.IO.Path.Combine(Store.Folder, "settings.json");

    public static Settings Load()
    {
        try
        {
            if (File.Exists(PathFile))
                return JsonSerializer.Deserialize<Settings>(File.ReadAllText(PathFile)) ?? new Settings();
        }
        catch (Exception ex) { Store.Log($"settings.json unreadable: {ex.Message}"); }
        return new Settings();
    }

    public void Save()
    {
        Store.WriteAtomic(PathFile, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        Changed?.Invoke();
    }

    // ---- Open at login (HKCU Run key) ----
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public static bool LoginEnabled()
    {
        try { using var k = Registry.CurrentUser.OpenSubKey(RunKey); return k?.GetValue("Memo") is string; }
        catch { return false; }
    }

    public static void SetLogin(bool on)
    {
        try
        {
            using var k = Registry.CurrentUser.CreateSubKey(RunKey);
            if (on && Environment.ProcessPath is { } exe) k.SetValue("Memo", $"\"{exe}\"");
            else k.DeleteValue("Memo", false);
        }
        catch (Exception ex) { Store.Log($"Open at login failed: {ex.Message}"); }
    }
}
