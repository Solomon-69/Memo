// logic-tests.swift: checks Memo's logic with a throwaway history folder (never the real one).
// Run: QA/test.sh
import AppKit

var failures = 0, passes = 0
func check(_ ok: Bool, _ name: String) {
    if ok { passes += 1 } else { failures += 1; print("FAIL: \(name)") }
}

@main
enum Tests {
    static func main() {
        // Links
        check(LinkCleaner.clean("https://ex.com/p?utm_source=x&fbclid=1&id=5&gclid=2") == "https://ex.com/p?id=5", "clean keeps real params")
        check(LinkCleaner.clean("https://ex.com/p?utm_medium=a") == "https://ex.com/p", "clean drops empty query")
        check(LinkCleaner.clean("https://youtu.be/abc?si=XYZ&t=10") == "https://youtu.be/abc?t=10", "youtube share id")
        check(LinkCleaner.clean("https://shop.com/?si=keep") == "https://shop.com/?si=keep", "si kept on other sites")
        check(LinkCleaner.clean("hello world") == nil, "plain text not a link")
        check(!LinkCleaner.isLink("ftp://x.com"), "ftp not treated as web link")
        // Colours
        check(ColorText.isColor("#2DD4BF") && ColorText.isColor("#fff") && ColorText.isColor("#11223344"), "hex colours")
        check(ColorText.isColor("rgb(10, 20, 30)") && ColorText.isColor("rgba(1,2,3,0.5)"), "rgb colours")
        check(!ColorText.isColor("#zzz") && !ColorText.isColor("123456") && !ColorText.isColor("rgb(300,1,1)"), "not colours")
        // Fuzzy
        check(Fuzzy.score("lun", in: "hello@lunashift.app") != nil, "substring match")
        check(Fuzzy.score("lun", in: "A very long piece of copied text that should never overflow the row or push the number") == nil, "no scattered match")
        check(Fuzzy.score("rpt", in: "Report.pdf") != nil, "letters in order")
        check((Fuzzy.score("rep", in: "Report") ?? 0) > (Fuzzy.score("rep", in: "a report") ?? 0), "start ranks higher")
        check(Fuzzy.score("zzz", in: "Report") == nil, "no match")
        // Markdown
        let link = ClipItem(id: 1, kind: .link, text: "https://ex.com/a", created: Date(), used: Date())
        check(Markdown.from(link) == "[ex.com/a](https://ex.com/a)", "link markdown")
        let md = Markdown.fromHTML("<p>Hi <b>bold</b> and <a href=\"https://x.com\">site</a></p>") ?? ""
        check(md.contains("**bold**") && md.contains("[site](https://x.com"), "html markdown: \(md)")
        // Pasting styles onto a private pasteboard (the real clipboard is untouched)
        let pb = NSPasteboard(name: .init("tenax-test-\(UUID().uuidString)"))
        var rich = ClipItem(id: 2, kind: .text, text: "Hi bold", created: Date(), used: Date())
        rich.html = "<b>Hi</b> bold"
        Paster.copy(rich, style: .normal, to: pb)
        check(pb.string(forType: .html) != nil && pb.data(forType: tenaxMarker) != nil, "normal paste keeps rich text + marker")
        Paster.copy(rich, style: .plain, to: pb)
        check(pb.string(forType: .html) == nil && pb.string(forType: .string) == "Hi bold", "plain paste drops formatting")
        Paster.copy(rich, style: .markdown, to: pb)
        check(pb.string(forType: .string) == "**Hi** bold", "markdown paste: \(pb.string(forType: .string) ?? "")")
        // Reading the clipboard
        pb.clearContents(); pb.setString("  #ff0000 ", forType: .string)
        check(ClipboardWatcher.read(pb, types: Set((pb.types ?? []).map(\.rawValue)))?.kind == .color, "reads colour")
        pb.clearContents(); pb.setString("https://a.com/x", forType: .string)
        check(ClipboardWatcher.read(pb, types: Set((pb.types ?? []).map(\.rawValue)))?.kind == .link, "reads link")
        pb.clearContents(); pb.setString("   ", forType: .string)
        check(ClipboardWatcher.read(pb, types: Set((pb.types ?? []).map(\.rawValue))) == nil, "ignores blank text")
        pb.clearContents(); pb.writeObjects([URL(fileURLWithPath: "/tmp") as NSURL])
        check(ClipboardWatcher.read(pb, types: Set((pb.types ?? []).map(\.rawValue)))?.kind == .file, "reads file")
        let img = NSImage(size: NSSize(width: 20, height: 10), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true }
        pb.clearContents(); pb.setData(img.tiffRepresentation!, forType: .tiff)
        let readImg = ClipboardWatcher.read(pb, types: Set((pb.types ?? []).map(\.rawValue))).flatMap(ClipboardWatcher.prepareImage)
        check(readImg?.kind == .image && readImg?.png != nil && readImg?.thumb != nil && readImg?.width == 20, "reads image with preview")
        check(Markdown.fromHTML("<p>x<img src=\"https://tracker.example/p.gif\"> <b>y</b></p>")?.contains("**y**") == true, "markdown strips remote images")
        var nul = NewClip(kind: .text, text: "a\u{0}b"); nul.source = nil
        check(!Set(["org.nspasteboard.ConcealedType"]).isDisjoint(with: Privacy.skipTypes), "concealed type is skipped")
        check(Privacy.passwordApps.contains("com.1password.1password"), "1Password skipped")
        pb.releaseGlobally()

        // Storage (TENAX_HOME is a temp folder)
        let st = Store.shared
        check(st.folder.path.hasPrefix("/private/tmp") || st.folder.path.hasPrefix("/tmp"), "test store is in temp folder")
        st.add(nul)
        check(st.all().first.map { st.full($0).text } == "a\u{0}b", "text with a NUL is kept whole")
        st.delete(st.all().first!.id)
        st.add(NewClip(kind: .text, text: "one"))
        st.add(NewClip(kind: .text, text: "one"))
        check(st.all().count == 1, "duplicate copy bumps instead of adding")
        st.add(NewClip(kind: .text, text: "two")); st.add(NewClip(kind: .text, text: "three"))
        check(st.all().first?.text == "three", "newest first")
        let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        st.add(NewClip(kind: .image, text: "", png: png, width: 20, height: 10))
        let imgItem = st.all().first { $0.kind == .image }
        check(imgItem?.image != nil && FileManager.default.fileExists(atPath: st.imagesDir.appendingPathComponent(imgItem!.image!).path), "image file saved")
        check(imgItem.flatMap { st.thumbnail($0.image!) } != nil, "thumbnail ready")
        st.delete(imgItem!.id)
        check(((try? FileManager.default.contentsOfDirectory(atPath: st.imagesDir.path)) ?? ["x"]).isEmpty, "delete removes image file")
        // Orphans both ways
        try? Data([1, 2, 3]).write(to: st.imagesDir.appendingPathComponent("stray.png"))
        st.add(NewClip(kind: .image, text: "", png: png + Data([0]), width: 20, height: 10))
        if let name = st.all().first(where: { $0.kind == .image })?.image {
            try? FileManager.default.removeItem(at: st.imagesDir.appendingPathComponent(name))
        }
        st.sweepOrphans()
        check(!FileManager.default.fileExists(atPath: st.imagesDir.appendingPathComponent("stray.png").path), "stray file removed")
        check(!st.all().contains { $0.kind == .image }, "row with missing image removed")
        // Pins and limits
        let ids = st.all().map(\.id)          // three, two, one
        st.setPinned(ids[2], true); st.setPinned(ids[1], true)
        let pins = st.all().filter(\.pinned).sorted { $0.pinOrder < $1.pinOrder }
        check(pins.map(\.id) == [ids[2], ids[1]], "pins stay in the order they were pinned")
        for i in 0..<10 { st.add(NewClip(kind: .text, text: "bulk \(i)")) }
        st.enforceLimits(keepDays: 0, maxItems: 3, maxBytes: 0)
        check(st.all().filter { !$0.pinned }.count == 3 && st.all().filter(\.pinned).count == 2, "item limit keeps pins")
        st.add(NewClip(kind: .text, text: String(repeating: "x", count: 50_000)))
        st.enforceLimits(keepDays: 0, maxItems: 0, maxBytes: 20_000)
        check(!st.all().contains { $0.text.count == 50_000 }, "size cap removes big old items")
        st.clearUnpinned()
        check(st.all().allSatisfy(\.pinned) && st.all().count == 2, "clear keeps pinned")
        check(st.diskBytes() > 0, "size is measured")
        // Opening a row shows the full text, not the 4,000-character list copy.
        st.add(NewClip(kind: .text, text: "Long one\n" + String(repeating: "y", count: 30_000)))
        st.add(NewClip(kind: .text, text: "short note"))
        let m = TenaxModel(); m.onLoadFull = { st.full($0) }; m.items = st.all()
        let long = m.visible.first { $0.text.hasPrefix("Long one") }!
        check(long.text.count <= 4_000, "list keeps a short copy")
        m.expand(long.id)
        check(m.expandedID == long.id && m.selectedID == long.id, "expand opens and selects the row")
        check(m.expandedText.count == TenaxModel.expandLimit && m.expandedTotal == 30_009, "expand loads full text, capped for display")
        m.toggleExpand(long.id)
        check(m.expandedID == nil, "toggle closes it again")
        m.expand(m.visible[0].id); m.move(1)
        check(m.expandedID == m.visible[1].id, "open row follows the selection")
        m.query = "short"
        check(m.expandedID == nil || m.visible.contains { $0.id == m.expandedID }, "open row closes when filtered out")
        m.query = ""; m.collapse()
        check(m.expandedID == nil, "collapse")
        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
