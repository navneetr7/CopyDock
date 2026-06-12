import SwiftUI
import SwiftData
import AppKit
import KeyboardShortcuts
import Combine

final class ClipyAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct ClipyApp: App {
    @NSApplicationDelegateAdaptor(ClipyAppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer

    @State private var historyStore: HistoryStore
    @State private var pasteboardMonitor: PasteboardMonitor
    @State private var writer: PasteboardWriter
    @State private var launchService = LaunchAtLoginService()
    @State private var settings = UserSettings.shared

    @State private var drawerPresenter: DrawerPresenter
    @State private var hotkeyManager: HotkeyManager

    @State private var repositionTask: Task<Void, Never>? = nil

    init() {
        do {
            modelContainer = try ModelContainer(for: ClipboardItem.self)
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
        }

        let context = modelContainer.mainContext
        let store = HistoryStore(modelContext: context)
        let categorizer = Categorizer()
        let blobs = BlobStore()
        let writer = PasteboardWriter()

        let monitor = PasteboardMonitor(
            categorizer: categorizer,
            blobStore: blobs,
            historyStore: store
        )

        let drawerContentFactory: () -> AnyView = { [store, writer] in
            AnyView(
                DrawerRootView(
                    onRestore: { item in
                        writer.write(item: item)
                    },
                    onDelete: { item in
                        Task { @MainActor in
                            try? await store.delete(item)
                        }
                    },
                    onTogglePin: { item in
                        try? await store.togglePin(item)
                    },
                    onClearAll: { includePinned in
                        try? await store.clearAll(includePinned: includePinned)
                    },
                    loadItems: {
                        (try? await store.fetchAll()) ?? []
                    },
                    settings: .shared
                )
            )
        }

        let presenter = DrawerPresenter(settings: .shared, contentView: drawerContentFactory)

        let hotkey = HotkeyManager {
            presenter.show()
        }

        _historyStore = State(initialValue: store)
        _pasteboardMonitor = State(initialValue: monitor)
        _writer = State(initialValue: writer)
        _drawerPresenter = State(initialValue: presenter)
        _hotkeyManager = State(initialValue: hotkey)

        Task { @MainActor [monitor] in
            NSApp.setActivationPolicy(.accessory)
            monitor.start()
        }
    }

    var body: some Scene {
        MenuBarExtra("Clipy", systemImage: "doc.on.clipboard.fill") {
            // ServiceStarter is a View, so it can hold @Environment(\.openWindow).
            // It handles both the startup kick and the openSettings notification —
            // things that can't be done directly from the App/Scene level.
            ServiceStarter(onStart: startMonitoringIfNeeded)

            Button("Open Clipy Drawer") {
                startMonitoringIfNeeded()
                drawerPresenter.show()
            }

            Divider()

            Button("Settings...") {
                // Post notification; ServiceStarter's onReceive calls openWindow(id: "settings")
                NotificationCenter.default.post(name: .openClipySettings, object: nil)
            }

            Button("Quit Clipy") {
                NSApplication.shared.terminate(nil)
            }
        }

        Window("Clipy Settings", id: "settings") {
            SettingsView(
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
            .environment(\.modelContext, modelContainer.mainContext)
            .onAppear {
                DispatchQueue.main.async {
                    if let window = NSApp.windows.first(where: { $0.title == "Clipy Settings" }) {
                        window.standardWindowButton(.zoomButton)?.isEnabled = false
                        window.styleMask.remove(.resizable)
                    }
                }
            }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 560)
    }


    private func startMonitoringIfNeeded() {
        NSApp.setActivationPolicy(.accessory)
        ClipyNotifier.configure()
        Task { _ = await ClipyNotifier.requestPermissionIfNeeded() }
        pasteboardMonitor.start()

        if settings.autoStart != launchService.isEnabled {
            try? launchService.setEnabled(settings.autoStart)
        }

        Task { @MainActor in
            try? await historyStore.prune(
                maxCount: settings.effectiveHistoryLimit,
                maxAgeDays: settings.retentionDays
            )
        }

        repositionTask?.cancel()
        repositionTask = Task { @MainActor in
            for await _ in Timer.publish(every: 1.5, on: .main, in: .common).autoconnect().values {
                guard !Task.isCancelled else { break }
                if drawerPresenter.isVisible {
                    drawerPresenter.repositionIfNeeded()
                }
            }
        }
    }
}


extension ClipyApp {
    /// Invisible view inside the MenuBarExtra.
    /// Starts services on first appear and handles the openSettings notification using
    /// @Environment(\.openWindow), which is only available inside a SwiftUI View.
    struct ServiceStarter: View {
        let onStart: () -> Void
        @Environment(\.openWindow) private var openWindow

        var body: some View {
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    onStart()
                }
                .onReceive(NotificationCenter.default.publisher(for: .openClipySettings)) { _ in
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
    }
}
