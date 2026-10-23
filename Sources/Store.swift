// Store.swift. Memo history storage: one SQLite file for the list, plus image files on disk.
//
// Fixes for common clipboard-manager storage bugs:
// - Every image file belongs to exactly one row. Rows whose file is missing and files with no row
//   are swept at launch and after each clean-up, so the store can never balloon with orphans.
// - A hard size cap (and age / count limits) is enforced after every new item.
// - A broken database is moved aside and replaced, so the history can never show blank forever.
import AppKit
import CryptoKit
import SQLite3

enum ClipKind: String, CaseIterable {
    case text, link, image, file, color

    var label: String {
        switch self {
        case .text: return "Text"
        case .link: return "Link"
        case .image: return "Image"
        case .file: return "File"
        case .color: return "Colour"
        }
    }
}

struct ClipItem: Identifiable, Equatable {
    let id: Int64
    var kind: ClipKind
    var text: String            // the text, link, file paths (one per line) or colour hex
    var html: String?           // rich text as HTML, used for "Paste as Markdown"
    var image: String?          // file name in images/ (and thumbs/)
    var width = 0, height = 0
    var source: String?         // app name it was copied from
    var created: Date
    var used: Date
    var pinned = false
    var pinOrder = 0
    var bytes = 0
    var cleaned = false         // tracking parameters were removed from this link
}

/// What the watcher hands to the store.
struct NewClip {
    var kind: ClipKind
    var text: String
    var html: String?
    var png: Data?
    var thumb: Data?
    var width = 0, height = 0
    var source: String?
    var cleaned = false
}

final class Store {
    static let shared = Store()

    let folder: URL
    let imagesDir: URL
    let thumbsDir: URL
    private var db: OpaquePointer?
    private let thumbCache = NSCache<NSString, NSImage>()
    private(set) var openError: String?

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        // TENAX_HOME lets the tests use a throwaway folder instead of the real history.
        if let home = ProcessInfo.processInfo.environment["TENAX_HOME"] {
            folder = URL(fileURLWithPath: home, isDirectory: true)
        } else {
            folder = base.appendingPathComponent("Memo", isDirectory: true)
            // The app was called Tenax first: carry its history over once.
            let old = base.appendingPathComponent("Tenax", isDirectory: true)
            if !FileManager.default.fileExists(atPath: folder.path), FileManager.default.fileExists(atPath: old.path) {
                try? FileManager.default.moveItem(at: old, to: folder)
            }
        }
        imagesDir = folder.appendingPathComponent("images", isDirectory: true)
        thumbsDir = folder.appendingPathComponent("thumbs", isDirectory: true)
        for dir in [folder, imagesDir, thumbsDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        thumbCache.countLimit = 300
        open()
    }

    private var dbURL: URL { folder.appendingPathComponent("history.sqlite") }

    // MARK: Opening (with self-repair)

    private func open() {
        if openAndMigrate() { return }
        // Corrupt or unreadable: keep a copy for safety, start fresh.
        Log.write("database unreadable, starting a fresh one")
        sqlite3_close(db); db = nil
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: dbURL.path + suffix)
            try? FileManager.default.moveItem(at: from, to: folder.appendingPathComponent("history-broken-\(stamp).sqlite\(suffix)"))
        }
        if !openAndMigrate() { openError = "Memo could not open its history file." }
    }

    private func openAndMigrate() -> Bool {
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { sqlite3_close(db); db = nil; return false }
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA busy_timeout=2000")
        let ok = exec("""
        CREATE TABLE IF NOT EXISTS items(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          kind TEXT NOT NULL, text TEXT NOT NULL, html TEXT, image TEXT,
          width INTEGER DEFAULT 0, height INTEGER DEFAULT 0, source TEXT,
          created REAL NOT NULL, used REAL NOT NULL,
          pinned INTEGER DEFAULT 0, pin_order INTEGER DEFAULT 0,
          bytes INTEGER DEFAULT 0, cleaned INTEGER DEFAULT 0,
          hash TEXT NOT NULL UNIQUE)
        """)
        guard ok else { return false }
        // A quick integrity check catches a damaged file before it shows an empty list.
        var healthy = false
        query("PRAGMA quick_check") { stmt in healthy = (column(stmt, 0) == "ok") }
        return healthy
    }

    // MARK: Reading

    func all() -> [ClipItem] {
        var out: [ClipItem] = []
        // The list only needs the start of each text; the full text is read when pasting.
        query("SELECT id,kind,substr(text,1,4000),NULL,image,width,height,source,created,used,pinned,pin_order,bytes,cleaned FROM items ORDER BY used DESC") { s in
            guard let kind = ClipKind(rawValue: column(s, 1) ?? "") else { return }
            out.append(ClipItem(
                id: sqlite3_column_int64(s, 0), kind: kind, text: column(s, 2) ?? "",
                html: column(s, 3), image: column(s, 4),
                width: Int(sqlite3_column_int(s, 5)), height: Int(sqlite3_column_int(s, 6)),
                source: column(s, 7),
                created: Date(timeIntervalSince1970: sqlite3_column_double(s, 8)),
                used: Date(timeIntervalSince1970: sqlite3_column_double(s, 9)),
                pinned: sqlite3_column_int(s, 10) != 0, pinOrder: Int(sqlite3_column_int(s, 11)),
                bytes: Int(sqlite3_column_int(s, 12)), cleaned: sqlite3_column_int(s, 13) != 0))
        }
        return out
    }

    // MARK: Writing

    /// Adds a new clip, or moves an identical existing one back to the top. Returns true if stored.
    @discardableResult
    func add(_ clip: NewClip) -> Bool {
        let hash = Self.hash(clip)
        let now = Date().timeIntervalSince1970
        // Same content copied again: just bump it to the top (no duplicate rows, no duplicate files).
        var existing: Int64?
        query("SELECT id FROM items WHERE hash=?", [hash]) { existing = sqlite3_column_int64($0, 0) }
        if let id = existing {
            run("UPDATE items SET used=?, source=COALESCE(?, source) WHERE id=?", [now, clip.source as Any, id])
            return true
        }
        var imageName: String?
        var bytes = clip.text.utf8.count + (clip.html?.utf8.count ?? 0)
        if let png = clip.png {
            let name = "\(hash.prefix(24)).png"
            let file = imagesDir.appendingPathComponent(name)
            do { try png.write(to: file, options: .atomic) } catch {
                Log.write("could not save image: \(error.localizedDescription)"); return false
            }
            bytes += png.count
            if let thumb = clip.thumb ?? Self.makeThumb(png) {
                try? thumb.write(to: thumbsDir.appendingPathComponent(name), options: .atomic)
                bytes += thumb.count
            }
            imageName = name
        }
        let ok = run("""
            INSERT INTO items(kind,text,html,image,width,height,source,created,used,bytes,cleaned,hash)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
            """, [clip.kind.rawValue, clip.text, clip.html as Any, imageName as Any, clip.width, clip.height,
                  clip.source as Any, now, now, bytes, clip.cleaned ? 1 : 0, hash])
        if !ok, let imageName { removeFiles(imageName) }
        return ok
    }

    /// The complete text and rich text of one item (the list holds a shortened copy).
    func full(_ item: ClipItem) -> ClipItem {
        var out = item
        query("SELECT text, html FROM items WHERE id=?", [item.id]) { s in
            out.text = column(s, 0) ?? item.text
            out.html = column(s, 1)
        }
        return out
    }

    func markUsed(_ id: Int64) { run("UPDATE items SET used=? WHERE id=?", [Date().timeIntervalSince1970, id]) }

    func setPinned(_ id: Int64, _ pinned: Bool) {
        var top = 0
        query("SELECT COALESCE(MAX(pin_order),0) FROM items WHERE pinned=1") { top = Int(sqlite3_column_int($0, 0)) }
        run("UPDATE items SET pinned=?, pin_order=? WHERE id=?", [pinned ? 1 : 0, pinned ? top + 1 : 0, id])
    }

    func delete(_ id: Int64) {
        var image: String?
        query("SELECT image FROM items WHERE id=?", [id]) { image = column($0, 0) }
        run("DELETE FROM items WHERE id=?", [id])
        if let image { removeFiles(image) }
    }

    /// Removes everything except pinned items.
    func clearUnpinned() {
        run("DELETE FROM items WHERE pinned=0")
        sweepOrphans()
        exec("VACUUM")
    }

    // MARK: Clean-up (age, count, size cap, orphans)

    /// keepDays 0 = forever. maxBytes is the hard cap for the whole history folder.
    func enforceLimits(keepDays: Int, maxItems: Int, maxBytes: Int) {
        if keepDays > 0 {
            let cutoff = Date().timeIntervalSince1970 - Double(keepDays) * 86_400
            deleteWhere("pinned=0 AND used < ?", [cutoff])
        }
        if maxItems > 0 {
            deleteWhere("pinned=0 AND id NOT IN (SELECT id FROM items WHERE pinned=0 ORDER BY used DESC LIMIT ?)", [maxItems])
        }
        // Size cap: drop the oldest unpinned items until the stored bytes fit.
        var total = 0
        query("SELECT COALESCE(SUM(bytes),0) FROM items") { total = Int(sqlite3_column_int64($0, 0)) }
        if maxBytes > 0, total > maxBytes {
            var drop: [Int64] = []
            var over = total - maxBytes
            // Never drop the item that was just copied.
            query("SELECT id, bytes FROM items WHERE pinned=0 AND id <> (SELECT id FROM items ORDER BY used DESC LIMIT 1) ORDER BY used ASC") { s in
                guard over > 0 else { return }
                drop.append(sqlite3_column_int64(s, 0)); over -= Int(sqlite3_column_int64(s, 1))
            }
            for id in drop { delete(id) }
        }
    }

    private func deleteWhere(_ condition: String, _ args: [Any]) {
        var images: [String] = []
        query("SELECT image FROM items WHERE image IS NOT NULL AND \(condition)", args) { s in
            if let n = column(s, 0) { images.append(n) }
        }
        run("DELETE FROM items WHERE \(condition)", args)
        images.forEach(removeFiles)
    }

    /// Rows whose image is gone are removed; image files that no row uses are deleted.
    func sweepOrphans() {
        var used = Set<String>()
        var missing: [Int64] = []
        query("SELECT id, image FROM items WHERE image IS NOT NULL") { s in
            guard let name = column(s, 1) else { return }
            if FileManager.default.fileExists(atPath: imagesDir.appendingPathComponent(name).path) {
                used.insert(name)
            } else {
                missing.append(sqlite3_column_int64(s, 0))
            }
        }
        for id in missing { run("DELETE FROM items WHERE id=?", [id]) }
        for dir in [imagesDir, thumbsDir] {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for f in files where !used.contains(f) {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
            }
        }
        if !missing.isEmpty { Log.write("removed \(missing.count) rows with missing images") }
    }

    /// Real size on disk of everything Memo keeps (database, its journal, images, thumbnails).
    func diskBytes() -> Int {
        var total = 0
        let fm = FileManager.default
        for name in ["history.sqlite", "history.sqlite-wal", "history.sqlite-shm"] {
            total += (try? fm.attributesOfItem(atPath: folder.appendingPathComponent(name).path)[.size] as? Int) ?? 0
        }
        for dir in [imagesDir, thumbsDir] {
            for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
                total += (try? fm.attributesOfItem(atPath: dir.appendingPathComponent(f).path)[.size] as? Int) ?? 0
            }
        }
        return total
    }

    func checkpoint() { exec("PRAGMA wal_checkpoint(TRUNCATE)") }

    // MARK: Images

    func imageURL(_ name: String) -> URL { imagesDir.appendingPathComponent(name) }

    /// Small preview, from memory, else from the thumbnail file made when it was copied.
    func thumbnail(_ name: String) -> NSImage? {
        if let hit = thumbCache.object(forKey: name as NSString) { return hit }
        let file = thumbsDir.appendingPathComponent(name)
        guard let img = NSImage(contentsOf: file) ?? NSImage(contentsOf: imagesDir.appendingPathComponent(name)) else { return nil }
        thumbCache.setObject(img, forKey: name as NSString)
        return img
    }

    private func removeFiles(_ name: String) {
        try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(name))
        try? FileManager.default.removeItem(at: thumbsDir.appendingPathComponent(name))
        thumbCache.removeObject(forKey: name as NSString)
    }

    static func makeThumb(_ png: Data, maxSide: CGFloat = 160) -> Data? {
        guard let src = NSImage(data: png), src.size.width > 0, src.size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(src.size.width, src.size.height))
        let w = max(1, Int(src.size.width * scale)), h = max(1, Int(src.size.height * scale))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        src.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    static func hash(_ clip: NewClip) -> String {
        var h = SHA256()
        h.update(data: Data(clip.kind.rawValue.utf8))
        h.update(data: Data(clip.text.utf8))
        if let png = clip.png { h.update(data: png) }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: SQLite helpers

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            Log.write("sql error: \(err.map { String(cString: $0) } ?? "?") in \(sql.prefix(60))")
            sqlite3_free(err)
            return false
        }
        return true
    }

    @discardableResult
    private func run(_ sql: String, _ args: [Any] = []) -> Bool {
        guard let stmt = prepare(sql, args) else { return false }
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            Log.write("sql step error \(rc): \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
        return true
    }

    private func query(_ sql: String, _ args: [Any] = [], _ row: (OpaquePointer) -> Void) {
        guard let stmt = prepare(sql, args) else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW { row(stmt) }
    }

    private func prepare(_ sql: String, _ args: [Any]) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            Log.write("sql prepare error: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            switch a {
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64: sqlite3_bind_int64(stmt, idx, v)
            case let v as Double: sqlite3_bind_double(stmt, idx, v)
            case let v as String: sqlite3_bind_text(stmt, idx, v, Int32(v.utf8.count), transient)
            case let v as String?: if let v { sqlite3_bind_text(stmt, idx, v, Int32(v.utf8.count), transient) } else { sqlite3_bind_null(stmt, idx) }
            default: sqlite3_bind_null(stmt, idx)
            }
        }
        return stmt
    }
}

private func column(_ stmt: OpaquePointer, _ i: Int32) -> String? {
    guard let c = sqlite3_column_text(stmt, i) else { return nil }
    let n = Int(sqlite3_column_bytes(stmt, i))   // full length, so text with a NUL isn't cut short
    return String(decoding: UnsafeBufferPointer(start: c, count: n), as: UTF8.self)
}

/// A plain file log (NSLog output is hidden on macOS 26).
enum Log {
    private static let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/Memo.log")
    private static let queue = DispatchQueue(label: "tenax.log")
    static func write(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        queue.async {
            let data = Data("\(stamp) \(line)\n".utf8)
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
