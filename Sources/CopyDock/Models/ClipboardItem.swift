import Foundation
import SwiftData

@Model
final class ClipboardItem {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var categoryRaw: String
    var sourceApp: String?
    var preview: String
    var contents: [HistoryItemContent]
    var isPinned: Bool = false
    var contentHash: String = ""

    var category: ClipboardCategory {
        get { ClipboardCategory(rawValue: categoryRaw) ?? .image }
        set { categoryRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        category: ClipboardCategory,
        contents: [HistoryItemContent],
        sourceApp: String? = nil,
        preview: String = "",
        contentHash: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.categoryRaw = category.rawValue
        self.contents = contents
        self.sourceApp = sourceApp
        self.preview = preview.isEmpty ? Self.makeDefaultPreview(from: contents) : preview
        self.contentHash = contentHash
    }

    private static func makeDefaultPreview(from contents: [HistoryItemContent]) -> String {
        if let text = contents.first(where: { $0.isString })?.stringValue {
            return String(text.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let urlStr = contents.first(where: { $0.isURL })?.stringValue {
            return urlStr
        }
        return "Clipboard item"
    }
}

struct HistoryItemContent: Codable, Identifiable, Hashable {
    var id = UUID()
    let type: String
    let value: Data?

    var stringValue: String? {
        guard let value else { return nil }
        return String(data: value, encoding: .utf8)
    }

    var isString: Bool {
        type == "public.utf8-plain-text" || type == "NSStringPboardType" || type == "public.text" || type.lowercased().contains("text")
    }

    var isURL: Bool {
        type == "public.url" || type == "public.file-url" || type.lowercased().contains("url")
    }

    var isFileURL: Bool {
        type == "public.file-url"
    }
}
