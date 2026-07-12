import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CopyDockImageView: View {
    let item: ClipboardItem
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.secondary.opacity(0.08)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.28))
                        .foregroundStyle(.secondary.opacity(0.35))
                }
            }
        }
        .task(id: item.id) { image = await loadImage() }
    }

    private func loadImage() async -> NSImage? {
        if let urlContent = item.contents.first(where: { $0.isFileURL }),
           let urlStr = urlContent.stringValue,
           let url = ImagePreviewLoader.fileURL(from: urlStr),
           FileManager.default.fileExists(atPath: url.path),
           ImagePreviewLoader.imageFileExtensions.contains(url.pathExtension.lowercased()),
           let img = NSImage(contentsOf: url) { return img }

        if let img = ImagePreviewLoader.loadImage(from: item) { return img }

        if let data = item.contents.first(where: { $0.type == "copydock.thumbnail" })?.value {
            return ImagePreviewLoader.imageFromData(data)
        }
        return nil
    }
}

struct DocIconView: View {
    let item: ClipboardItem
    var compact: Bool = false
    var iconSize: CGFloat = 40

    private var fileExtension: String {
        if let urlContent = item.contents.first(where: { $0.isFileURL }),
           let urlStr = urlContent.stringValue,
           let url = URL(string: urlStr) {
            let ext = url.pathExtension
            if !ext.isEmpty { return ext }
        }
        if let blobPath = item.contents.first(where: { $0.type == "copydock.blob" })?.stringValue {
            let ext = (blobPath as NSString).pathExtension
            if !ext.isEmpty { return ext }
        }
        return "doc"
    }

    private var systemIcon: NSImage {
        if let uti = UTType(filenameExtension: fileExtension) {
            return NSWorkspace.shared.icon(for: uti)
        }
        return NSWorkspace.shared.icon(for: .data)
    }

    var body: some View {
        let size = compact ? min(iconSize, 34) : iconSize
        Image(nsImage: systemIcon)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

struct RecentItemCard: View {
    let item: ClipboardItem
    var cardWidth: CGFloat = 120
    var cardHeight: CGFloat = 90
    var flipAngle: Double = 0
    var isHovered: Bool = false
    let onTap: () -> Void
    var onPastePlain: () -> Void = {}
    var onTogglePin: () -> Void = {}
    var onRemove: () -> Void = {}

    @State private var appIcon: NSImage?
    @State private var appName: String?

    private let cornerRadius: CGFloat = 12
    private let cardBorderOpacity: CGFloat = 0.12
    private let cardBackgroundBrighten: CGFloat = 0.04
    private let headerHeight: CGFloat = 29

    private var isImage: Bool { item.category == .image }
    private var isDoc:   Bool { item.category == .doc   }

    private var iconSize: CGFloat { min(cardWidth, cardHeight) * 0.38 }
    private let bodyFontSize: CGFloat = 12
    private var textLineLimit: Int { max(1, Int((cardHeight - headerHeight - 24) / 15)) }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    private static let timeWithMinFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let timeHourOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "h a"
        return f
    }()

    private var timestampString: String {
        let mins = Calendar.current.component(.minute, from: item.timestamp)
        let time = mins == 0
            ? Self.timeHourOnlyFormatter.string(from: item.timestamp)
            : Self.timeWithMinFormatter.string(from: item.timestamp)
        return "\(Self.dateTimeFormatter.string(from: item.timestamp)) · \(time)"
    }

    var body: some View {
        cardBody
            .overlay {
                CopyDockCardDragLayer(item: item, onTap: onTap, onPastePlain: onPastePlain, onTogglePin: onTogglePin, onRemove: onRemove)
            }
            .overlay(alignment: .topTrailing) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Color.accentColor))
                        .padding(5)
                }
            }
            .padding(.bottom, 2)
            .rotation3DEffect(
                .degrees(flipAngle),
                axis: (x: 0, y: 1, z: 0),
                anchor: flipAngle > 0 ? .leading : flipAngle < 0 ? .trailing : .center,
                perspective: 0.2
            )
            .task(id: item.sourceApp) {
                guard let bundleID = item.sourceApp else { return }
                appIcon = AppIconCache.shared.icon(for: bundleID)
                appName = AppIconCache.shared.name(for: bundleID)
            }
    }

    private var cardBody: some View {
        VStack(spacing: 0) {
            cardHeader
            Divider()
                .overlay(Color.white.opacity(0.18))
            cardContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                cardShape.fill(.regularMaterial)
                cardShape.fill(Color.white.opacity(cardBackgroundBrighten))
            }
        }
        .clipShape(cardShape)
        .overlay {
            cardShape.strokeBorder(
                isHovered ? Color.white.opacity(0.28) : Color.primary.opacity(cardBorderOpacity),
                lineWidth: isHovered ? 0.75 : 0.5
            )
        }
        .shadow(color: .black.opacity(isHovered ? 0.16 : 0.1), radius: isHovered ? 7 : 4, x: 0, y: isHovered ? 4 : 2)
        .shadow(
            color: .black.opacity(isHovered ? 0.08 : 0.06),
            radius: isHovered ? 3 : 2,
            x: flipAngle > 0 ? -2 : flipAngle < 0 ? 2 : 0,
            y: 1
        )
    }

    private var cardHeader: some View {
        HStack(spacing: 5) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: 17, height: 17)
            }
            Text(appName ?? "")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(timestampString)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: headerHeight)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.28))
    }

    private var cardContent: some View {
        Group {
            if isImage {
                CopyDockImageView(item: item)
            } else if isDoc {
                docBody
            } else {
                textBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var textBody: some View {
        Text(item.preview.isEmpty ? "Untitled" : item.preview)
            .font(.system(size: bodyFontSize))
            .lineLimit(textLineLimit)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
    }

    private var docBody: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            DocIconView(item: item, iconSize: iconSize)
            Text(docFileName)
                .font(.system(size: bodyFontSize))
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var docFileName: String {
        if let urlContent = item.contents.first(where: { $0.isFileURL }),
           let urlStr = urlContent.stringValue,
           let url = URL(string: urlStr) {
            return url.lastPathComponent
        }
        if !item.preview.isEmpty, !item.preview.hasPrefix("file://") { return item.preview }
        return "Document"
    }
}

struct MacTrafficLights: View {
    enum Kind { case close, minimize }

    let onClose: () -> Void
    let onMinimize: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            trafficLight(.close,    color: Color(red: 1.0, green: 0.37, blue: 0.34), action: onClose)
            trafficLight(.minimize, color: Color(red: 1.0, green: 0.74, blue: 0.18), action: onMinimize)
        }
        .padding(.leading, 6)
    }

    private let trafficLightSize: CGFloat = 16
    private let trafficLightIconSize: CGFloat = 7

    private func trafficLight(_ kind: Kind, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .overlay { Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5) }
                Image(systemName: symbol(for: kind))
                    .font(.system(size: trafficLightIconSize, weight: .heavy))
                    .foregroundStyle(Color.black.opacity(0.62))
            }
            .frame(width: trafficLightSize, height: trafficLightSize)
        }
        .buttonStyle(.plain)
        .help(help(for: kind))
    }

    private func symbol(for kind: Kind) -> String {
        switch kind {
        case .close:    return "xmark"
        case .minimize: return "minus"
        }
    }

    private func help(for kind: Kind) -> String {
        switch kind {
        case .close:    return "Close"
        case .minimize: return "Minimize"
        }
    }
}
