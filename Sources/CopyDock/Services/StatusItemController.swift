import AppKit

@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = statusImage()
            button.imagePosition = .imageOnly
            button.toolTip = "CopyDock"
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        statusItem = item
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            openDrawer()
            return
        }

        if event.type == .rightMouseUp {
            showMenu()
        } else {
            openDrawer()
        }
    }

    @objc private func openDrawer() {
        NotificationCenter.default.post(name: .openCopyDockDrawer, object: nil)
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .openCopyDockSettings, object: nil)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func showMenu() {
        guard let statusItem, let button = statusItem.button else { return }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open CopyDock", action: #selector(openDrawer), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit CopyDock", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func statusImage() -> NSImage? {
        let image = Bundle.main.image(forResource: "copydock_menubar")
            ?? NSImage(named: "copydock_menubar")
            ?? NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: "CopyDock")

        image?.size = NSSize(width: 18, height: 18)
        return image
    }
}

