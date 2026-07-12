import Foundation

enum ClipboardCategory: String, CaseIterable, Codable, Hashable {
    // Raw values are persisted in SwiftData — don't change them.
    case text = "Text"
    case link = "Link"
    case doc = "Doc"
    case image = "Other"

    var displayName: String {
        switch self {
        case .text:  return "Text"
        case .link:  return "Links"
        case .doc:   return "Documents"
        case .image: return "Images"
        }
    }

    var systemImage: String {
        switch self {
        case .text:  return "text.alignleft"
        case .link:  return "link"
        case .doc:   return "doc.text"
        case .image: return "photo.on.rectangle"
        }
    }

    static var displayOrder: [ClipboardCategory] { [.text, .link, .doc, .image] }
}
