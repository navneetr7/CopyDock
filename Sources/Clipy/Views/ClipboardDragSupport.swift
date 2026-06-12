import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

func dragFileURL(from contents: [HistoryItemContent]) -> URL? {
    ImagePreviewLoader.fileURL(from: contents.first(where: { $0.isFileURL })?.stringValue)
}

func dragUTI(forExtension ext: String) -> String {
    UTType(filenameExtension: ext.lowercased())?.identifier ?? UTType.data.identifier
}

func dragImageUTI(for item: ClipboardItem, data: Data) -> String {
    if let blobPath = item.contents.first(where: { $0.type == "clipy.blob" })?.stringValue {
        let ext = (blobPath as NSString).pathExtension
        if !ext.isEmpty { return dragUTI(forExtension: ext) }
    }
    if let fileURL = dragFileURL(from: item.contents), !fileURL.pathExtension.isEmpty {
        return dragUTI(forExtension: fileURL.pathExtension)
    }
    for type in dragPreferredImageTypes {
        if item.contents.contains(where: { $0.type == type }) { return type }
    }
    if let source = CGImageSourceCreateWithData(data as CFData, nil),
       let typeID = CGImageSourceGetType(source) as String? {
        return typeID
    }
    return UTType.png.identifier
}

let dragPreferredImageTypes = [
    "public.png", "public.tiff", "com.apple.tiff", "NSTIFFPboardType",
    "public.jpeg", "public.jpg", "public.heic", "public.heif", "public.image"
]

func dragDocFilename(for item: ClipboardItem, ext: String) -> String {
    if let fileURL = dragFileURL(from: item.contents), !fileURL.lastPathComponent.isEmpty {
        return fileURL.lastPathComponent
    }
    let trimmed = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty, !trimmed.hasPrefix("file://"), trimmed != "Document" {
        if (trimmed as NSString).pathExtension.isEmpty, !ext.isEmpty { return "\(trimmed).\(ext)" }
        return trimmed
    }
    return ext.isEmpty ? "Document" : "Document.\(ext)"
}

func dragPNGData(from data: Data) -> Data? {
    guard let image = ImagePreviewLoader.imageFromData(data),
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return bitmap.representation(using: .png, properties: [:])
}

func dragTIFFData(from data: Data) -> Data? {
    guard let image = ImagePreviewLoader.imageFromData(data) else { return nil }
    return image.tiffRepresentation
}

func dragSessionPreview(for item: ClipboardItem) -> NSImage? {
    switch item.category {
    case .other:
        return ImagePreviewLoader.loadImage(from: item)
    case .doc:
        if let fileURL = dragFileURL(from: item.contents) {
            return NSWorkspace.shared.icon(forFile: fileURL.path)
        }
        if let blobPath = item.contents.first(where: { $0.type == "clipy.blob" })?.stringValue {
            let ext = (blobPath as NSString).pathExtension
            if let uti = UTType(filenameExtension: ext) { return NSWorkspace.shared.icon(for: uti) }
        }
        return NSWorkspace.shared.icon(for: .pdf)
    default:
        return nil
    }
}

struct ClipyCardDragLayer: NSViewRepresentable {
    let item: ClipboardItem
    let onTap: () -> Void
    let onTogglePin: () -> Void
    let onRemove: () -> Void

    func makeNSView(context: Context) -> CardDragSourceView {
        let view = CardDragSourceView()
        view.item = item
        view.onTap = onTap
        view.onTogglePin = onTogglePin
        view.onRemove = onRemove
        return view
    }

    func updateNSView(_ nsView: CardDragSourceView, context: Context) {
        nsView.item = item
        nsView.onTap = onTap
        nsView.onTogglePin = onTogglePin
        nsView.onRemove = onRemove
    }
}

final class CardDragSourceView: NSView, NSDraggingSource {
    var item: ClipboardItem?
    var onTap: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onRemove: (() -> Void)?

    private var pressLocation: NSPoint?
    private var sessionStarted = false
    private let dragThresholdSquared: CGFloat = 36

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressLocation = NSEvent.mouseLocation
        sessionStarted = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !sessionStarted, let item, let pressLocation else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - pressLocation.x
        let dy = current.y - pressLocation.y
        guard dx * dx + dy * dy >= dragThresholdSquared else { return }

        sessionStarted = true
        NotificationCenter.default.post(name: .clipyDrawerDragDidBegin, object: nil)

        let writer = pasteboardWriter(for: item)
        let draggingItem = NSDraggingItem(pasteboardWriter: writer)
        let preview = dragSessionPreview(for: item) ?? NSImage(size: bounds.size)
        draggingItem.setDraggingFrame(bounds, contents: preview)
        _ = beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !sessionStarted { onTap?() }
        pressLocation = nil
        sessionStarted = false
    }

    override func rightMouseDown(with event: NSEvent) {
        let pasteItem = NSMenuItem(title: "Paste to Clipboard", action: #selector(handlePaste), keyEquivalent: "")
        pasteItem.target = self
        let pinTitle = (item?.isPinned == true) ? "Unpin" : "Pin"
        let pinItem = NSMenuItem(title: pinTitle, action: #selector(handleTogglePin), keyEquivalent: "")
        pinItem.target = self
        let removeItem = NSMenuItem(title: "Remove", action: #selector(handleRemove), keyEquivalent: "")
        removeItem.target = self
        removeItem.attributedTitle = NSAttributedString(string: "Remove", attributes: [.foregroundColor: NSColor.systemRed])
        let menu = NSMenu()
        menu.addItem(pasteItem)
        menu.addItem(.separator())
        menu.addItem(pinItem)
        menu.addItem(.separator())
        menu.addItem(removeItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func handlePaste()      { onTap?() }
    @objc private func handleTogglePin()  { onTogglePin?() }
    @objc private func handleRemove()     { onRemove?() }

    private func pasteboardWriter(for item: ClipboardItem) -> NSPasteboardWriting {
        let store = BlobStore()
        switch item.category {

        case .text:
            return (item.contents.first(where: { $0.isString })?.stringValue ?? item.preview) as NSString

        case .link:
            if let urlStr = item.contents.first(where: { $0.isURL })?.stringValue,
               let url = URL(string: urlStr) { return url as NSURL }
            return item.preview as NSString

        case .other:
            if let fileURL = dragFileURL(from: item.contents),
               FileManager.default.fileExists(atPath: fileURL.path) { return fileURL as NSURL }
            if let data = ImagePreviewLoader.loadData(from: item, store: store) {
                let pItem = NSPasteboardItem()
                if let pngData = dragPNGData(from: data) {
                    pItem.setData(pngData, forType: NSPasteboard.PasteboardType(UTType.png.identifier))
                }
                if let tiffData = dragTIFFData(from: data) {
                    pItem.setData(tiffData, forType: .tiff)
                }
                if pItem.types.isEmpty {
                    pItem.setData(data, forType: NSPasteboard.PasteboardType(dragImageUTI(for: item, data: data)))
                }
                return pItem
            }
            return item.preview as NSString

        case .doc:
            if let fileURL = dragFileURL(from: item.contents),
               FileManager.default.fileExists(atPath: fileURL.path) { return fileURL as NSURL }
            if let blobPath = item.contents.first(where: { $0.type == "clipy.blob" })?.stringValue,
               let data = try? store.load(relativePath: blobPath) {
                let ext = (blobPath as NSString).pathExtension
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("clipy_\(UUID().uuidString)_\(dragDocFilename(for: item, ext: ext))")
                if (try? data.write(to: tmp)) != nil { return tmp as NSURL }
            }
            if let pdfContent = item.contents.first(where: { $0.type.contains("pdf") }),
               let data = pdfContent.value {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("clipy_\(UUID().uuidString)_\(dragDocFilename(for: item, ext: "pdf"))")
                if (try? data.write(to: tmp)) != nil { return tmp as NSURL }
                let pItem = NSPasteboardItem()
                pItem.setData(data, forType: NSPasteboard.PasteboardType(UTType.pdf.identifier))
                return pItem
            }
            return item.preview as NSString
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        NotificationCenter.default.post(name: .clipyDrawerDragDidEnd, object: nil, userInfo: ["operation": operation.rawValue])
        sessionStarted = false
        pressLocation = nil
    }
}
