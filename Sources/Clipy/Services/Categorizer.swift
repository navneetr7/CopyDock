import AppKit
import UniformTypeIdentifiers

protocol Categorizing {
    func categorize(pasteboardItem: NSPasteboardItem, sourceApp: String?) -> ClipboardCategory
    func categorizeFromContents(_ contents: [HistoryItemContent]) -> ClipboardCategory
}

final class Categorizer: Categorizing {

    func categorize(pasteboardItem item: NSPasteboardItem, sourceApp: String?) -> ClipboardCategory {
        let types = Set(item.types.map { $0.rawValue })

        if types.contains("public.file-url") || types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) {
            if let urlString = item.string(forType: .fileURL) ?? item.string(forType: NSPasteboard.PasteboardType("public.file-url")),
               let url = URL(string: urlString) {
                return categoryForFileURL(url)
            }
            return .doc
        }

        if types.contains(NSPasteboard.PasteboardType.URL.rawValue) || types.contains("public.url") {
            return .link
        }

        if let string = item.string(forType: .string) ?? item.string(forType: NSPasteboard.PasteboardType("public.utf8-plain-text")) {
            if isClearlyALink(string) { return .link }
        }

        if types.contains(NSPasteboard.PasteboardType.pdf.rawValue) || types.contains("com.adobe.pdf") {
            return .doc
        }

        if types.contains(NSPasteboard.PasteboardType.png.rawValue) ||
           types.contains(NSPasteboard.PasteboardType.tiff.rawValue) ||
           types.contains("public.image") ||
           types.contains("public.jpeg") ||
           types.contains("public.png") {
            return .other
        }

        if let string = item.string(forType: .string), let url = URL(string: string), url.pathExtension.lowercased().isDocExtension {
            return .doc
        }

        if item.string(forType: .string) != nil { return .text }

        return .other
    }

    func categorizeFromContents(_ contents: [HistoryItemContent]) -> ClipboardCategory {
        let typeSet = Set(contents.map { $0.type })

        if typeSet.contains(where: { $0.contains("file-url") || $0.contains("public.file-url") }) {
            if let fileContent = contents.first(where: { $0.isFileURL }),
               let url = fileContent.stringValue.flatMap(URL.init(string:)) {
                return categoryForFileURL(url)
            }
            return .doc
        }

        if contents.contains(where: { ImagePreviewLoader.looksLikeImageContent($0) }) {
            return .other
        }

        if typeSet.contains("public.url") || typeSet.contains(NSPasteboard.PasteboardType.URL.rawValue) {
            return .link
        }

        if let textContent = contents.first(where: { $0.isString })?.stringValue {
            if isClearlyALink(textContent) { return .link }
        }

        if typeSet.contains("com.adobe.pdf") || typeSet.contains(NSPasteboard.PasteboardType.pdf.rawValue) {
            return .doc
        }

        if contents.contains(where: { $0.isString }) { return .text }

        return .other
    }

    private func isClearlyALink(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("www.") {
            return true
        }

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            return true
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        if let match = detector?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
            return match.range.length == trimmed.utf16.count || match.url != nil
        }

        return false
    }

    private func categoryForFileURL(_ url: URL) -> ClipboardCategory {
        let ext = url.pathExtension.lowercased()
        if ext.isDocExtension { return .doc }
        if ["png", "jpg", "jpeg", "gif", "heic", "tiff", "mov", "mp4", "avi"].contains(ext) { return .other }
        return .doc
    }
}

private extension String {
    var isDocExtension: Bool {
        let docs: Set<String> = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "rtf", "odt", "ods", "odp"]
        return docs.contains(self)
    }
}
