import AppKit
import UniformTypeIdentifiers

protocol PasteboardWriting {
    func write(item: ClipboardItem, plainTextOnly: Bool) -> Bool
}

final class PasteboardWriter: PasteboardWriting {

    private let pasteboard = NSPasteboard.general
    // Lets other clipboard managers (and our own monitor) recognise our writes.
    private let markerType = NSPasteboard.PasteboardType("org.nspasteboard.CopyDock")

    func write(item: ClipboardItem, plainTextOnly: Bool = false) -> Bool {
        if plainTextOnly, let text = item.contents.first(where: { $0.isString })?.stringValue {
            pasteboard.clearContents()
            let ok = pasteboard.setString(text, forType: .string)
            pasteboard.setString("1", forType: markerType)
            return ok
        }

        pasteboard.clearContents()
        var success = false
        let store = BlobStore()
        pasteboard.setString("1", forType: markerType)

        for content in item.contents {
            if content.type.hasPrefix("copydock.") {
                if content.type == "copydock.blob", let path = content.stringValue,
                   let data = try? store.load(relativePath: path) {
                    let ext = (path as NSString).pathExtension
                    let uti = ext.isEmpty ? "public.data" : (UTType(filenameExtension: ext)?.identifier ?? "public.data")
                    if pasteboard.setData(data, forType: NSPasteboard.PasteboardType(uti)) { success = true }
                }
                continue
            }

            if let data = content.value {
                if pasteboard.setData(data, forType: NSPasteboard.PasteboardType(content.type)) { success = true }
            } else if let string = content.stringValue {
                if pasteboard.setString(string, forType: NSPasteboard.PasteboardType(content.type)) { success = true }
            }
        }

        if !success {
            if let text = item.contents.first(where: { $0.isString })?.stringValue {
                pasteboard.setString(text, forType: .string)
                success = true
            } else if let fileStr = item.contents.first(where: { $0.isFileURL })?.stringValue,
                      let url = URL(string: fileStr) {
                pasteboard.writeObjects([url as NSURL])
                success = true
            }
        }

        return success
    }
}
