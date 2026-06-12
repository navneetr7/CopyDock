import Foundation

enum ClipboardCategory: String, CaseIterable, Codable, Hashable {
    case text = "Text"
    case link = "Link"
    case doc = "Doc"
    case other = "Other"

    var systemImage: String {
        switch self {
        case .text:  return "text.alignleft"
        case .link:  return "link"
        case .doc:   return "doc.text"
        case .other: return "photo.on.rectangle"
        }
    }

    static var displayOrder: [ClipboardCategory] { [.text, .link, .doc, .other] }
}
