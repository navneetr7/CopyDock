import SwiftUI
import SwiftData
import AppKit
import KeyboardShortcuts
import Combine

@MainActor
final class ClipyAppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemController = StatusItemController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItemController.install()
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
    private let settingsWindowController: SettingsWindowController

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

        let drawerContentFactory: () -> AnyView = { [store, writer, monitor] in
            AnyView(
                DrawerRootView(
                    onRestore: { item in
                        let success = writer.write(item: item)
                        monitor.skipCurrentPasteboardChange()
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
            forName: .openClipyDrawer,
            object: nil,
            queue: .main
        ) { [monitor, store, presenter] _ in
            MainActor.assumeIsolated {
                Self.startServices(monitor: monitor, store: store)
                presenter.show()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .openClipySettings,
            object: nil,
            queue: .main
        ) { [settingsWindowController] _ in
            MainActor.assumeIsolated {
                settingsWindowController.show()
            }
        }

        Task { @MainActor [monitor] in
            NSApp.setActivationPolicy(.accessory)
            monitor.start()
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
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

    @MainActor
    private static func startServices(monitor: PasteboardMonitor, store: HistoryStore) {
        let settings = UserSettings.shared
        NSApp.setActivationPolicy(.accessory)
        ClipyNotifier.configure()
        Task { _ = await ClipyNotifier.requestPermissionIfNeeded() }
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
