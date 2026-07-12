import SwiftUI
import SwiftData
import AppKit
import KeyboardShortcuts
import Combine

@MainActor
final class CopyDockAppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemController = StatusItemController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        CopyDockNotifier.configure()
        Paster.install()
        statusItemController.install()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct CopyDockApp: App {
    @NSApplicationDelegateAdaptor(CopyDockAppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer

    @State private var historyStore: HistoryStore
    @State private var pasteboardMonitor: PasteboardMonitor
    @State private var writer: PasteboardWriter
    @State private var launchService = LaunchAtLoginService()
    @State private var settings = UserSettings.shared

    @State private var drawerPresenter: DrawerPresenter
    @State private var hotkeyManager: HotkeyManager

    private let settingsWindowController: SettingsWindowController

    init() {
        do {
            modelContainer = try ModelContainer(for: ClipboardItem.self)
        } catch {
            // Store is unreadable (e.g. schema changed without a migration). Clipboard
            // history is disposable — recreate the store rather than crash-loop at login.
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(
                    at: URL.applicationSupportDirectory.appending(path: "default.store\(suffix)")
                )
            }
            do {
                modelContainer = try ModelContainer(for: ClipboardItem.self)
            } catch {
                fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
            }
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

        let drawerContentFactory: () -> AnyView = { [store, writer, monitor] in
            AnyView(
                DrawerRootView(
                    onRestore: { item, plainText in
                        let success = writer.write(item: item, plainTextOnly: plainText)
                        monitor.skipCurrentPasteboardChange()
                        if success, UserSettings.shared.pasteDirectly {
                            if Paster.isTrusted {
                                // Wait for the drawer to minimize and focus to return.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    Paster.pasteIntoTargetApp()
                                }
                            } else {
                                Paster.requestAccess()
                            }
                        }
                        return success
                    },
                    onDelete: { item in
                        do {
                            try await store.delete(item)
                        } catch {
                            print("HistoryStore delete failed: \(error)")
                        }
                    },
                    onTogglePin: { item in
                        do {
                            try await store.togglePin(item)
                        } catch {
                            print("HistoryStore toggle pin failed: \(error)")
                        }
                    },
                    onClearAll: { includePinned in
                        do {
                            try await store.clearAll(includePinned: includePinned)
                        } catch {
                            print("HistoryStore clear all failed: \(error)")
                        }
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

        let settingsWindowController = SettingsWindowController(
            modelContext: context,
            historyStore: store
        )

        _historyStore = State(initialValue: store)
        _pasteboardMonitor = State(initialValue: monitor)
        _writer = State(initialValue: writer)
        _drawerPresenter = State(initialValue: presenter)
        _hotkeyManager = State(initialValue: hotkey)
        self.settingsWindowController = settingsWindowController

        NotificationCenter.default.addObserver(
            forName: .openCopyDockDrawer,
            object: nil,
            queue: .main
        ) { [monitor, store, presenter] _ in
            MainActor.assumeIsolated {
                Self.startServices(monitor: monitor, store: store)
                presenter.show()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .openCopyDockSettings,
            object: nil,
            queue: .main
        ) { [settingsWindowController] _ in
            MainActor.assumeIsolated {
                settingsWindowController.show()
            }
        }

        Task { @MainActor [monitor, store] in
            NSApp.setActivationPolicy(.accessory)

            // Remove blob files no longer referenced by any history item
            // (leaked when a save fails or the app dies mid-insert).
            // Must finish before the monitor starts so an in-flight capture's
            // freshly saved blob can't be mistaken for an orphan.
            if let items = try? await store.fetchAll() {
                let live = Set(items.flatMap { item in
                    item.contents.compactMap { $0.type == "copydock.blob" ? $0.stringValue : nil }
                })
                BlobStore().cleanupOrphaned(currentRelativePaths: live)
            }

            monitor.start()
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }

    @MainActor
    private static func startServices(monitor: PasteboardMonitor, store: HistoryStore) {
        let settings = UserSettings.shared
        NSApp.setActivationPolicy(.accessory)
        CopyDockNotifier.configure()
        Task { _ = await CopyDockNotifier.requestPermissionIfNeeded() }
        monitor.start()

        let launchService = LaunchAtLoginService()
        if settings.autoStart != launchService.isEnabled {
            try? launchService.setEnabled(settings.autoStart)
        }

        Task { @MainActor in
            try? await store.prune(
                maxCount: settings.effectiveHistoryLimit,
                maxAgeDays: settings.retentionDays
            )
        }
    }
}
