// Describer.swift. Short labels for long text, links and pictures, made on this Mac.
// Uses Apple's own on-device model (Apple Intelligence) and the Vision framework: free, no account,
// nothing is sent anywhere. Where the Mac has no on-device model, rows simply keep their normal titles.
import AppKit
import Foundation
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

enum Describer {
    /// Short items already read fine as they are.
    static func wantsLabel(_ item: ClipItem) -> Bool {
        switch item.kind {
        case .image, .link: return true
        case .text: return item.text.count > 48 || item.text.contains("\n")
        case .file, .color: return false
        }
    }

    static var modelReady: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// One label of at most a few words, or nil if nothing sensible came out.
    static func label(kind: ClipKind, text: String, imageURL: URL?) async -> String? {
        var material = String(text.prefix(1500))
        if kind == .image, let imageURL {
            let facts = await Task.detached(priority: .utility) { imageFacts(at: imageURL) }.value
            material = facts
            if material.isEmpty { return nil }
        }
        if material.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), modelReady {
            let task: String
            switch kind {
            case .image:
                task = "Say what this picture shows, using the classifier results and any text read from it. If it has readable text, say what that text is about. Examples: 'Screenshot of a sales chart', 'Photo of a dog on a beach', 'Receipt from Tesco'."
            case .link:
                task = "Name the website and what the page is about, guessed from the address. Examples: 'Apple App Store page for a notes app', 'YouTube video about sourdough', 'GitHub repo for Memo'."
            default:
                task = "Say what the text is about or what it asks for. Examples: 'Request to review the sales report', 'Recipe for banana bread', 'Swift code for a login screen'."
            }
            let session = LanguageModelSession(instructions: """
                You label clipboard items. Reply with ONLY a label of at most 7 words, in the same language as the \
                content. No quotes, no full stop, no preamble. \(task)
                """)
            let prompt = "Content:\n\n\(material)"
            if let reply = try? await session.respond(to: prompt) {
                return clean(reply.content)
            }
        }
        #endif
        return nil
    }

    private static func clean(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”‘’.•-: "))
        if let nl = s.firstIndex(of: "\n") { s = String(s[..<nl]) }
        guard !s.isEmpty, s.count <= 60 else { return nil }
        return s
    }

    /// What Vision sees in a picture: the main things in it and any words printed on it.
    private static func imageFacts(at url: URL) -> String {
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        let classify = VNClassifyImageRequest()
        let read = VNRecognizeTextRequest()
        read.recognitionLevel = .fast
        read.usesLanguageCorrection = true
        try? handler.perform([classify, read])
        let generic: Set<String> = ["structure", "material", "others", "text", "document", "screenshot_other"]
        let things = (classify.results ?? [])
            .filter { $0.confidence > 0.25 && !generic.contains($0.identifier) }
            .prefix(4).map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        let words = (read.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
        var out: [String] = []
        if !things.isEmpty { out.append("Looks like: " + things.joined(separator: ", ")) }
        if !words.isEmpty { out.append("Text in it: " + String(words.prefix(700))) }
        if out.isEmpty { out.append("Picture \(cg.width) by \(cg.height) pixels with nothing recognisable") }
        return out.joined(separator: "\n")
    }
}
