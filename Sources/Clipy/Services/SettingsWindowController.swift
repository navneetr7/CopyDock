import AppKit
import SwiftData
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let modelContext: ModelContext
    private let historyStore: HistoryStore
    private var window: NSWindow?

    init(modelContext: ModelContext, historyStore: HistoryStore) {
        self.modelContext = modelContext
        self.historyStore = historyStore
    }

    func show() {
        let existing = window ?? makeWindow()
        window = existing
        existing.center()
        existing.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsView(
            onClearAll: { [historyStore] includePinned in
                try? await historyStore.clearAll(includePinned: includePinned)
            },
            onLimitsChanged: { [historyStore] in
                let settings = UserSettings.shared
                try? await historyStore.prune(
                    maxCount: settings.effectiveHistoryLimit,
                    maxAgeDays: settings.retentionDays
                )
            }
        )
        .environment(\.modelContext, modelContext)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clipy Settings"
        window.contentView = NSHostingView(rootView: root)
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        return window
    }
}
