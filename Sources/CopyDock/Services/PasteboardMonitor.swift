import AppKit
import CryptoKit
import Foundation

@MainActor
final class PasteboardMonitor {

    private let categorizer: Categorizing
    private let blobStore: BlobStoring
    private let historyStore: HistoryStoring
    private let writerMarkerType = NSPasteboard.PasteboardType("org.nspasteboard.CopyDock")

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private var isPaused = false
    private var keepAliveActivity: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastSeenHash: String?

    var onNewItem: ((ClipboardItem) -> Void)?

    init(
        categorizer: Categorizing = Categorizer(),
        blobStore: BlobStoring = BlobStore(),
        historyStore: HistoryStoring
    ) {
        self.categorizer = categorizer
        self.blobStore = blobStore
        self.historyStore = historyStore
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        stop()

        keepAliveActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated],
            reason: "Monitoring clipboard history"
        )

        let pollTimer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForChanges() }
        }
        RunLoop.main.add(pollTimer, forMode: .common)
        timer = pollTimer

        installWorkspaceObservers()
        checkForChanges()
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        if let keepAliveActivity {
            ProcessInfo.processInfo.endActivity(keepAliveActivity)
            self.keepAliveActivity = nil
        }

        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { center.removeObserver(observer) }
        workspaceObservers.removeAll()
    }

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.checkForChanges() }
            },
            center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.checkForChanges() }
            },
            center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.checkForChanges() }
            },
        ]
    }

    func pause() { isPaused = true }
    func resume() { isPaused = false; checkForChanges() }

    func skipCurrentPasteboardChange() {
        lastChangeCount = pasteboard.changeCount
    }

    private func checkForChanges() {
        guard !isPaused else { return }

        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let sourceApp, UserSettings.shared.excludedAppIDs.contains(sourceApp) { return }

        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return }

        var allContents: [HistoryItemContent] = []
        var primaryItemForCategory: NSPasteboardItem?

        for item in items {
            if shouldIgnore(item) { continue }
            primaryItemForCategory = primaryItemForCategory ?? item

            let hasFileURL = item.types.contains(NSPasteboard.PasteboardType("public.file-url"))

            for type in item.types {
                if type == writerMarkerType { continue }

                let raw = type.rawValue
                if raw.hasPrefix("dyn.") || raw.hasPrefix("com.microsoft.ole.source.") { continue }

                if hasFileURL && raw != "public.file-url" && raw != "public.url" {
                    continue
                }

                if let data = item.data(forType: type) {
                    allContents.append(HistoryItemContent(type: raw, value: data))
                } else if let str = item.string(forType: type), let data = str.data(using: .utf8) {
                    allContents.append(HistoryItemContent(type: raw, value: data))
                }
            }
        }

        guard !allContents.isEmpty else { return }

        // Stable across launches so duplicates can be detected against stored history.
        var hashInput = Data()
        if let primaryText = allContents.first(where: {
            $0.type == "public.utf8-plain-text" || $0.type == "NSStringPboardType"
        })?.value {
            hashInput = primaryText
        } else if let anyText = allContents.first(where: { $0.isString })?.value {
            hashInput = anyText
        } else if let urlVal = allContents.first(where: { $0.isURL })?.value {
            hashInput = urlVal
        } else if let biggest = allContents.compactMap({ c -> (String, Data)? in
            guard let d = c.value, d.count > 0 else { return nil }
            return (c.type, d)
        }).max(by: { $0.1.count < $1.1.count }) {
            hashInput = Data(biggest.0.utf8) + biggest.1.prefix(4096)
        }
        let signature = SHA256.hash(data: hashInput).map { String(format: "%02x", $0) }.joined()
        if signature == lastSeenHash { return }
        lastSeenHash = signature

        let category = categorizer.categorizeFromContents(allContents)

        let isFileURLItem = allContents.contains { $0.isFileURL }
        var finalContents = allContents

        if !isFileURLItem {
            if category == .image {
                if let thumbData = makeThumbnailPNG(from: allContents, maxDim: 512) {
                    finalContents.append(HistoryItemContent(type: "copydock.thumbnail", value: thumbData))
                }
            }

            let largeItems = finalContents.filter {
                $0.type != "copydock.thumbnail" && ($0.value?.count ?? 0) > 100_000
            }
            for large in largeItems {
                guard let data = large.value else { continue }
                let ext: String
                if large.type.contains("pdf")        { ext = "pdf"  }
                else if large.type.contains("png")   { ext = "png"  }
                else if large.type.contains("tiff")  { ext = "tiff" }
                else if large.type.contains("jpeg") || large.type.contains("jpg") { ext = "jpg" }
                else                                 { ext = "bin"  }
                if let rel = try? blobStore.save(data: data, preferredExtension: ext) {
                    finalContents.removeAll { $0.id == large.id }
                    finalContents.append(HistoryItemContent(type: "copydock.blob", value: rel.data(using: .utf8)))
                } else {
                    finalContents.removeAll { $0.id == large.id }
                }
            }
        }

        let preview = makePreview(from: allContents, category: category)
        let newItem = ClipboardItem(category: category, contents: finalContents, sourceApp: sourceApp, preview: preview, contentHash: signature)

        Task {
            do {
                // Copying something already in history moves the existing item to the top.
                if try await historyStore.bumpDuplicate(contentHash: signature) {
                    NotificationCenter.default.post(name: .clipboardItemsDidChange, object: nil)
                    return
                }

                try await historyStore.insert(newItem)
                onNewItem?(newItem)
                NotificationCenter.default.post(name: .clipboardItemsDidChange, object: nil)

                if isFileURLItem,
                   let urlStr = finalContents.first(where: { $0.isFileURL })?.stringValue,
                   let fileURL = ImagePreviewLoader.fileURL(from: urlStr) {
                    if let thumbData = await ThumbnailGenerator.generate(for: fileURL, maxDim: 512) {
                        newItem.contents.append(HistoryItemContent(type: "copydock.thumbnail", value: thumbData))
                        try await historyStore.saveChanges()
                        NotificationCenter.default.post(name: .clipboardItemsDidChange, object: nil)
                    }
                }
            } catch {
                print("HistoryStore insert failed: \(error)")
            }
        }
    }

    private func makeThumbnailPNG(from contents: [HistoryItemContent], maxDim: CGFloat) -> Data? {
        let preferredTypes = [
            "public.png", "public.tiff", "com.apple.tiff",
            "public.jpeg", "NSBitmapImageRep", "public.image"
        ]
        var imageData: Data?
        for t in preferredTypes {
            if let d = contents.first(where: { $0.type == t })?.value { imageData = d; break }
        }
        if imageData == nil {
            for c in contents {
                let t = c.type.lowercased()
                guard t.contains("image") || t.contains("png") || t.contains("tiff") || t.contains("jpeg") else { continue }
                guard let d = c.value, d.count > 512 else { continue }
                imageData = d; break
            }
        }
        if imageData == nil {
            for c in contents where c.isFileURL {
                guard let urlStr = c.stringValue,
                      let url = URL(string: urlStr),
                      ImagePreviewLoader.imageFileExtensions.contains(url.pathExtension.lowercased()),
                      let data = try? Data(contentsOf: url) else { continue }
                imageData = data; break
            }
        }
        guard let imageData,
              let nsImage = NSImage(data: imageData),
              nsImage.size.width > 0, nsImage.size.height > 0 else { return nil }

        let sz = nsImage.size
        let scale = min(maxDim / sz.width, maxDim / sz.height, 1.0)
        let thumbSize = NSSize(width: sz.width * scale, height: sz.height * scale)

        let thumb = NSImage(size: thumbSize)
        thumb.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .medium
        nsImage.draw(in: NSRect(origin: .zero, size: thumbSize), from: NSRect(origin: .zero, size: sz), operation: .copy, fraction: 1.0)
        thumb.unlockFocus()

        guard let tiff = thumb.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func shouldIgnore(_ item: NSPasteboardItem) -> Bool {
        let types = item.types.map { $0.rawValue }

        if types.contains("org.nspasteboard.ConcealedType") ||
           types.contains("org.nspasteboard.TransientType") ||
           types.contains("org.nspasteboard.AutoGeneratedType") {
            return true
        }

        if let str = item.string(forType: .string), str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let hasRich = item.data(forType: .rtf) != nil || item.data(forType: .html) != nil
            if !hasRich { return true }
        }

        return false
    }

    private func makePreview(from contents: [HistoryItemContent], category: ClipboardCategory) -> String {
        if let text = contents.first(where: { $0.isString })?.stringValue {
            return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(category == .link ? 200 : 80))
        }
        if let urlStr = contents.first(where: { $0.isURL })?.stringValue { return urlStr }
        switch category {
        case .doc: return "Document"
        case .image: return "Image or media"
        default: return "Clipboard content"
        }
    }
}
