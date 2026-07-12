import AppKit
import UniformTypeIdentifiers

protocol Categorizing {
    func categorizeFromContents(_ contents: [HistoryItemContent]) -> ClipboardCategory
}

final class Categorizer: Categorizing {

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
            return .image
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

        return .image
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
        if ["png", "jpg", "jpeg", "gif", "heic", "tiff", "mov", "mp4", "avi"].contains(ext) { return .image }
        return .doc
    }
}

private extension String {
    var isDocExtension: Bool {
        let docs: Set<String> = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "rtf", "odt", "ods", "odp"]
        return docs.contains(self)
    }
}
