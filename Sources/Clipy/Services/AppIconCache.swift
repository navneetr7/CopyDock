import AppKit

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private var icons: [String: NSImage] = [:]
    private var names: [String: String] = [:]

    func icon(for bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = iconFromBundle(at: url) ?? NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = image
        return image
    }

    func name(for bundleID: String) -> String? {
        if let cached = names[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        names[bundleID] = name
        return name
    }

    private func iconFromBundle(at appURL: URL) -> NSImage? {
        guard let bundle = Bundle(url: appURL),
              let iconName = bundle.infoDictionary?["CFBundleIconFile"] as? String else { return nil }
        let resources = appURL.appendingPathComponent("Contents/Resources")
        for candidate in [resources.appendingPathComponent(iconName),
                          resources.appendingPathComponent("\(iconName).icns")] {
            if let image = NSImage(contentsOf: candidate) { return image }
        }
        return nil
    }
}
