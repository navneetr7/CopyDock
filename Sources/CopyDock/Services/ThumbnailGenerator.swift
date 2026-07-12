import AppKit
import AVFoundation
import QuickLookThumbnailing
import UniformTypeIdentifiers

enum ThumbnailGenerator {

    static func generate(for url: URL, maxDim: CGFloat = 260) async -> Data? {
        let ext = url.pathExtension.lowercased()

        if ImagePreviewLoader.imageFileExtensions.contains(ext) {
            return await imageFileThumbnail(url: url, maxDim: maxDim)
        }

        if ext == "mp4" || ext == "mov" || ext == "m4v" || ext == "avi" || ext == "mkv" {
            return await videoThumbnail(url: url, maxDim: maxDim)
        }

        return await quickLookThumbnail(url: url, maxDim: maxDim)
    }

    private static func imageFileThumbnail(url: URL, maxDim: CGFloat) async -> Data? {
        guard let data = try? Data(contentsOf: url),
              let image = ImagePreviewLoader.imageFromData(data) else { return nil }
        return scaled(image, maxDim: maxDim)
    }

    private static func videoThumbnail(url: URL, maxDim: CGFloat) async -> Data? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxDim, height: maxDim)
        guard let cgImage = try? await gen.image(at: .zero).image else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return scaled(image, maxDim: maxDim)
    }

    private static func quickLookThumbnail(url: URL, maxDim: CGFloat) async -> Data? {
        let size = CGSize(width: maxDim, height: maxDim)
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: size, scale: 1,
            representationTypes: .thumbnail
        )
        guard let thumb = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return workspaceIcon(url: url, maxDim: maxDim)
        }
        return scaled(NSImage(cgImage: thumb.cgImage, size: size), maxDim: maxDim)
    }

    private static func workspaceIcon(url: URL, maxDim: CGFloat) -> Data? {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        return scaled(icon, maxDim: maxDim)
    }

    private static func scaled(_ image: NSImage, maxDim: CGFloat) -> Data? {
        let sz = image.size
        guard sz.width > 0, sz.height > 0 else { return nil }
        let scale = min(maxDim / sz.width, maxDim / sz.height, 1.0)
        let thumbSize = NSSize(width: sz.width * scale, height: sz.height * scale)

        let thumb = NSImage(size: thumbSize)
        thumb.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .medium
        image.draw(in: NSRect(origin: .zero, size: thumbSize),
                   from: NSRect(origin: .zero, size: sz),
                   operation: .copy, fraction: 1.0)
        thumb.unlockFocus()

        guard let tiff = thumb.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
