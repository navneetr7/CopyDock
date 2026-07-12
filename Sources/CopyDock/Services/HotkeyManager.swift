import Foundation
import KeyboardShortcuts
import AppKit

@MainActor
final class HotkeyManager {

    private let onTrigger: () -> Void

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        setup()
    }

    private func setup() {
        KeyboardShortcuts.onKeyUp(for: UserSettings.shortcutName) { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated { self.onTrigger() }
        }
    }

    /// Call this if the user changes the shortcut in settings (the package handles most of it).
    func refresh() {
        // KeyboardShortcuts automatically updates observers when the shortcut changes.
    }
}
