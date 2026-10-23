using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Memo;

internal enum Kind { Text, Image, Files }

internal sealed class ClipItem
{
    public long Id { get; set; }
    public Kind Kind { get; set; }
    public string Text { get; set; } = "";          // text, or the file paths joined by new lines
    public string? ImageFile { get; set; }          // PNG name inside the images folder
    public int Width { get; set; }
    public int Height { get; set; }
    public string App { get; set; } = "";
    public DateTime Time { get; set; } = DateTime.UtcNow;
    public bool Pinned { get; set; }
    public string Hash { get; set; } = "";

    [System.Text.Json.Serialization.JsonIgnore]
    public string[] Files => Kind == Kind.Files ? Text.Split('\n', StringSplitOptions.RemoveEmptyEntries) : Array.Empty<string>();

    [System.Text.Json.Serialization.JsonIgnore]
    public bool IsColor => Kind == Kind.Text && Regex.IsMatch(Text.Trim(), "^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$");

    [System.Text.Json.Serialization.JsonIgnore]
    public bool IsLink => Kind == Kind.Text && Text.Length < 2000 && !Text.Contains(' ') && !Text.Contains('\n') &&
                          Uri.TryCreate(Text.Trim(), UriKind.Absolute, out var u) && (u.Scheme == "http" || u.Scheme == "https");

    public string Title => Kind switch
    {
        Kind.Image => $"Image  {Width} x {Height}",
        Kind.Files => Files.Length == 1 ? System.IO.Path.GetFileName(Files[0]) : $"{Files.Length} files",
        _ => string.Join(" ", Text.Split(new[] { '\r', '\n', '\t' }, StringSplitOptions.RemoveEmptyEntries)).Trim(),
    };
}

/// <summary>
/// Everything Memo keeps on disk, under %APPDATA%\Memo: history.json, images\*.png, settings.json, memo.log.
/// The history is also the in-memory list the popup shows.
/// </summary>
internal sealed class Store
{
    public static string Folder { get; set; } = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Memo");
    public static string ImagesFolder => System.IO.Path.Combine(Folder, "images");
    private static string HistoryPath => System.IO.Path.Combine(Folder, "history.json");
    private static string LogPath => System.IO.Path.Combine(Folder, "memo.log");

    private readonly Settings settings;
    public List<ClipItem> Items { get; private set; } = new();
    public event Action? Changed;

    public Store(Settings settings)
    {
        this.settings = settings;
        Load();
        Prune();
    }

    // ---- Disk ----

    public static void Log(string line)
    {
        try { Directory.CreateDirectory(Folder); File.AppendAllText(LogPath, $"{DateTime.Now:s} {line}\n"); } catch { }
    }

    public static void WriteAtomic(string path, string text)
    {
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
            var tmp = path + ".tmp";
            File.WriteAllText(tmp, text);
            File.Move(tmp, path, true);
        }
        catch (Exception ex) { Log($"Could not write {path}: {ex.Message}"); }
    }

    private void Load()
    {
        try
        {
            if (File.Exists(HistoryPath))
                Items = JsonSerializer.Deserialize<List<ClipItem>>(File.ReadAllText(HistoryPath)) ?? new();
        }
        catch (Exception ex) { Log($"history.json unreadable: {ex.Message}"); Items = new(); }
    }

    public void Save() => WriteAtomic(HistoryPath, JsonSerializer.Serialize(Items));

    /// <summary>Reads the history back from disk into a fresh list (used by the self-test).</summary>
    public static List<ClipItem> ReadFromDisk()
    {
        try { return JsonSerializer.Deserialize<List<ClipItem>>(File.ReadAllText(HistoryPath)) ?? new(); }
        catch { return new(); }
    }

    // ---- Adding ----

    private ClipItem Upsert(Kind kind, string text, string? imageFile, int w, int h, string app, string hash)
    {
        var existing = Items.FirstOrDefault(i => i.Hash == hash);
        if (existing != null)
        {
            existing.Time = DateTime.UtcNow;
            if (app.Length > 0) existing.App = app;
            Commit();
            return existing;
        }
        var item = new ClipItem
        {
            Id = Items.Count == 0 ? 1 : Items.Max(i => i.Id) + 1,
            Kind = kind, Text = text, ImageFile = imageFile, Width = w, Height = h, App = app, Hash = hash,
        };
        Items.Add(item);
        Commit();
        return item;
    }

    public ClipItem? AddText(string text, string app)
    {
        if (string.IsNullOrWhiteSpace(text) || text.Length > 2_000_000) return null;
        if (settings.CleanLinks) text = CleanLink(text);
        return Upsert(Kind.Text, text, null, 0, 0, app, Sha(Encoding.UTF8.GetBytes(text)));
    }

    public ClipItem? AddFiles(IEnumerable<string> paths, string app)
    {
        var list = paths.Where(p => !string.IsNullOrWhiteSpace(p)).ToArray();
        if (list.Length == 0) return null;
        var text = string.Join("\n", list);
        return Upsert(Kind.Files, text, null, 0, 0, app, Sha(Encoding.UTF8.GetBytes("files:" + text)));
    }

    public ClipItem? AddImage(Image image, string app)
    {
        using var ms = new MemoryStream();
        image.Save(ms, System.Drawing.Imaging.ImageFormat.Png);
        var bytes = ms.ToArray();
        var hash = Sha(bytes);
        var name = hash[..16] + ".png";
        Directory.CreateDirectory(ImagesFolder);
        var file = System.IO.Path.Combine(ImagesFolder, name);
        if (!File.Exists(file)) File.WriteAllBytes(file, bytes);
        return Upsert(Kind.Image, "", name, image.Width, image.Height, app, hash);
    }

    private static string Sha(byte[] b) => Convert.ToHexString(SHA256.HashData(b));

    // ---- Links ----

    private static readonly string[] TrackingParams = { "fbclid", "gclid", "dclid", "msclkid", "mc_eid", "mc_cid", "igshid", "yclid", "_hsenc", "_hsmi", "ref_src" };

    /// <summary>Takes tracking bits (utm_source, fbclid and friends) off a copied web link; anything else is untouched.</summary>
    public static string CleanLink(string text)
    {
        var t = text.Trim();
        if (t.Length > 2000 || t.Contains(' ') || t.Contains('\n') || !Uri.TryCreate(t, UriKind.Absolute, out var u) ||
            (u.Scheme != "http" && u.Scheme != "https") || string.IsNullOrEmpty(u.Query)) return text;
        var q = t.IndexOf('?');
        var hash = t.IndexOf('#');
        var end = hash >= 0 && hash > q ? hash : t.Length;
        var tail = t[end..];
        var keep = t[(q + 1)..end].Split('&', StringSplitOptions.RemoveEmptyEntries).Where(p =>
        {
            var key = p.Split('=')[0].ToLowerInvariant();
            return !key.StartsWith("utm_") && !TrackingParams.Contains(key);
        }).ToArray();
        return t[..q] + (keep.Length > 0 ? "?" + string.Join("&", keep) : "") + tail;
    }

    // ---- Changing ----

    public void Touch(ClipItem item) { item.Time = DateTime.UtcNow; Commit(); }
    public void TogglePin(ClipItem item) { item.Pinned = !item.Pinned; Commit(); }

    public void Delete(ClipItem item)
    {
        Items.Remove(item);
        Commit();
    }

    public void ClearUnpinned()
    {
        Items.RemoveAll(i => !i.Pinned);
        Commit();
    }

    private void Commit()
    {
        Prune();
        Save();
        Changed?.Invoke();
    }

    /// <summary>Keeps to the History settings. Pinned items always stay.</summary>
    public void Prune()
    {
        var cutoff = DateTime.UtcNow.AddDays(-Math.Max(1, settings.KeepDays));
        Items.RemoveAll(i => !i.Pinned && i.Time < cutoff);
        var loose = Items.Where(i => !i.Pinned).OrderByDescending(i => i.Time).ToList();
        foreach (var extra in loose.Skip(Math.Max(1, settings.MaxItems))) Items.Remove(extra);

        long limit = Math.Max(1, settings.MaxMegabytes) * 1024L * 1024L;
        foreach (var old in Items.Where(i => !i.Pinned && i.Kind == Kind.Image).OrderBy(i => i.Time).ToList())
        {
            if (ImageBytes() <= limit) break;
            Items.Remove(old);
        }
        RemoveOrphanImages();
    }

    public long ImageBytes()
    {
        long total = 0;
        foreach (var i in Items.Where(x => x.Kind == Kind.Image && x.ImageFile != null))
        {
            try { total += new FileInfo(System.IO.Path.Combine(ImagesFolder, i.ImageFile!)).Length; } catch { }
        }
        return total;
    }

    public long DiskBytes()
    {
        long total = ImageBytes();
        try { total += new FileInfo(HistoryPath).Length; } catch { }
        return total;
    }

    private void RemoveOrphanImages()
    {
        try
        {
            if (!Directory.Exists(ImagesFolder)) return;
            var used = Items.Where(i => i.ImageFile != null).Select(i => i.ImageFile!).ToHashSet();
            foreach (var f in Directory.GetFiles(ImagesFolder, "*.png"))
                if (!used.Contains(System.IO.Path.GetFileName(f))) File.Delete(f);
        }
        catch (Exception ex) { Log($"Cleanup failed: {ex.Message}"); }
    }

    // ---- Reading for the list ----

    /// <summary>Pinned first, then newest first; filtered by the search words.</summary>
    public List<ClipItem> Search(string query)
    {
        var q = query.Trim();
        IEnumerable<ClipItem> all = Items;
        if (q.Length > 0)
            all = all.Where(i =>
                (i.Kind == Kind.Image ? "image picture screenshot" : i.Text).Contains(q, StringComparison.OrdinalIgnoreCase) ||
                i.App.Contains(q, StringComparison.OrdinalIgnoreCase));
        return all.OrderByDescending(i => i.Pinned).ThenByDescending(i => i.Time).ToList();
    }

    public static Bitmap? LoadImage(ClipItem item)
    {
        try
        {
            if (item.ImageFile == null) return null;
            using var ms = new MemoryStream(File.ReadAllBytes(System.IO.Path.Combine(ImagesFolder, item.ImageFile)));
            using var img = Image.FromStream(ms);
            return new Bitmap(img);
        }
        catch { return null; }
    }
}
