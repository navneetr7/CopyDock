import AppKit
import UniformTypeIdentifiers

protocol PasteboardWriting {
    func write(item: ClipboardItem) -> Bool
}

final class PasteboardWriter: PasteboardWriting {

    private let pasteboard = NSPasteboard.general

    func write(item: ClipboardItem) -> Bool {
        pasteboard.clearContents()
        var success = false
        let store = BlobStore()

        for content in item.contents {
            if content.type.hasPrefix("clipy.") {
                if content.type == "clipy.blob", let path = content.stringValue,
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
