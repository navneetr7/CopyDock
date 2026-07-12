import SwiftUI

/// Switches between the full drawer and the minimized edge strip.
struct DrawerRootView: View {
    @State private var isMinimized = false

    let onRestore:   (ClipboardItem, _ plainText: Bool) -> Bool
    let onDelete:    @MainActor (ClipboardItem) async -> Void
    let onTogglePin: @MainActor (ClipboardItem) async -> Void
    let onClearAll:  @MainActor (Bool) async -> Void
    let loadItems:   @MainActor () async -> [ClipboardItem]
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
        .onReceive(NotificationCenter.default.publisher(for: .copydockDrawerDidMinimize)) { _ in
            isMinimized = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .copydockDrawerDidExpand)) { _ in
            isMinimized = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .copydockDrawerWillShow)) { _ in
            isMinimized = false
        }
    }
}
