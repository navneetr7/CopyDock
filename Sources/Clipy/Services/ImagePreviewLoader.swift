import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImagePreviewLoader {

    static let imageFileExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "webp", "bmp", "svg"
    ]

    private static let imageTypeHints = [
        "image", "png", "jpeg", "jpg", "tiff", "bmp", "gif", "heic", "heif", "webp", "icns", "bitmap"
    ]

    private static let preferredInlineTypes = [
        "public.png", "public.tiff", "com.apple.tiff", "NSTIFFPboardType",
        "public.jpeg", "public.jpg", "public.heic", "public.heif",
        "public.image", "NSBitmapImageRep", "Apple PNG pasteboard type"
    ]

    static func hasImageData(in item: ClipboardItem) -> Bool {
        item.contents.contains { looksLikeImageContent($0) }
    }

    static func loadData(from item: ClipboardItem, store: BlobStoring = BlobStore()) -> Data? {
        for content in item.contents where content.type == "clipy.blob" {
            if let path = content.stringValue,
               let data = try? store.load(relativePath: path),
               imageFromData(data) != nil {
                return data
            }
        }

        for type in preferredInlineTypes {
            if let data = item.contents.first(where: { $0.type == type })?.value,
               imageFromData(data) != nil {
                return data
            }
        }

        for content in item.contents where looksLikeImageContent(content) {
            if let data = content.value, imageFromData(data) != nil { return data }
        }

        for content in item.contents {
            let type = content.type.lowercased()
            guard !type.contains("text"), !type.contains("url"), !type.contains("string"),
                  !type.contains("html"), !type.contains("rtf"), type != "clipy.blob" else { continue }
            guard let data = content.value, data.count > 512, imageFromData(data) != nil else { continue }
            return data
        }

        return loadDataFromFileURL(in: item.contents)
    }

    static func loadImage(from item: ClipboardItem, store: BlobStoring = BlobStore()) -> NSImage? {
        if let data = loadData(from: item, store: store) { return imageFromData(data) }
        return loadImageFromFileURL(in: item.contents)
    }

    static func looksLikeImageContent(_ content: HistoryItemContent) -> Bool {
        let type = content.type.lowercased()
        if imageTypeHints.contains(where: { type.contains($0) }) { return true }

        if content.type == "clipy.blob", let path = content.stringValue?.lowercased() {
            return imageFileExtensions.contains { path.hasSuffix(".\($0)") }
        }

        if content.isFileURL, let url = fileURL(from: content.stringValue) {
            return imageFileExtensions.contains(url.pathExtension.lowercased())
        }

        return false
    }

    static func imageFromData(_ data: Data) -> NSImage? {
        if let image = NSImage(data: data), image.isValid, image.size.width > 0, image.size.height > 0 {
            return image
        }

        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }

        if let rep = NSBitmapImageRep(data: data) {
            let image = NSImage(size: rep.size)
            image.addRepresentation(rep)
            return image.isValid ? image : nil
        }

        return nil
    }

    private static func loadDataFromFileURL(in contents: [HistoryItemContent]) -> Data? {
        guard let url = firstImageFileURL(in: contents),
              let data = try? Data(contentsOf: url) else { return nil }
        return imageFromData(data) != nil ? data : nil
    }

    private static func loadImageFromFileURL(in contents: [HistoryItemContent]) -> NSImage? {
        guard let url = firstImageFileURL(in: contents) else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func firstImageFileURL(in contents: [HistoryItemContent]) -> URL? {
        for content in contents where content.isFileURL {
            guard let url = fileURL(from: content.stringValue),
                  FileManager.default.fileExists(atPath: url.path),
                  imageFileExtensions.contains(url.pathExtension.lowercased()) else { continue }
            return url
        }
        return nil
    }

    static func fileURL(from string: String?) -> URL? {
        guard let string, !string.isEmpty else { return nil }
        if let url = URL(string: string), url.isFileURL { return url }
        if string.hasPrefix("/") { return URL(fileURLWithPath: string) }
        return nil
    }
}
