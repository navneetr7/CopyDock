import SwiftUI

/// Switches between the full drawer and the minimized edge strip.
struct DrawerRootView: View {
    @State private var isMinimized = false

    let onRestore:   (ClipboardItem) -> Bool
    let onDelete:    (ClipboardItem) -> Void
    let onTogglePin: (ClipboardItem) async -> Void
    let onClearAll:  (Bool) async -> Void
    let loadItems:   () async -> [ClipboardItem]
    let settings:    UserSettings

    var body: some View {
        Group {
            if isMinimized {
                MinimizedDrawerStrip()
            } else {
                ClipboardDrawerView(
                    onRestore: onRestore,
                    onDelete: onDelete,
                    onTogglePin: onTogglePin,
                    onClearAll: onClearAll,
                    loadItems: loadItems,
                    settings: settings
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipyDrawerDidMinimize)) { _ in
            isMinimized = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipyDrawerDidExpand)) { _ in
            isMinimized = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipyDrawerWillShow)) { _ in
            isMinimized = false
        }
    }
}