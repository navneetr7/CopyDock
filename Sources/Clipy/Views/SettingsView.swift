import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var settings = UserSettings.shared
    @State private var launchService = LaunchAtLoginService()
    @State private var isClearing = false
    @State private var isResetting = false
    @State private var clearIncludesPinned = false
    @State private var showFeedback = false
    @FocusState private var focusedLimitField: LimitField?

    var onClearAll: (Bool) async -> Void
    var onLimitsChanged: () async -> Void = {}

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.autoStart },
                    set: { newValue in
                        settings.autoStart = newValue
                        do {
                            try launchService.setEnabled(newValue)
                        } catch {
                            // Revert visual state on failure
                            settings.autoStart = launchService.isEnabled
                            showFeedback = true
                        }
                    }
                ))
                .onAppear {
                    // Sync visual state with reality (user may have toggled via system settings)
                    if settings.autoStart != launchService.isEnabled {
                        settings.autoStart = launchService.isEnabled
                    }
                }

                Stepper(value: $settings.retentionDays, in: 1...365) {
                    Text("Keep Clipboard History for \(settings.retentionDays) Days")
                        .monospacedDigit()
                }
                Text("Older items are automatically removed to keep your clipboard tidy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("History Limits") {
                ItemLimitEditor(
                    field: .history,
                    focusedField: $focusedLimitField,
                    title: "Saved clipboard items",
                    caption: "Maximum unpinned items kept in history. Pinned items are not counted.",
                    isUnlimited: $settings.historyLimitUnlimited,
                    count: $settings.historyLimitCount,
                    defaultCount: UserSettings.defaultHistoryLimitCount,
                    range: UserSettings.historyLimitRange
                )

                ItemLimitEditor(
                    field: .pinned,
                    focusedField: $focusedLimitField,
                    title: "Pinned items",
                    caption: "Maximum number of items you can pin at once.",
                    isUnlimited: $settings.pinnedLimitUnlimited,
                    count: $settings.pinnedLimitCount,
                    defaultCount: UserSettings.defaultPinnedLimitCount,
                    range: UserSettings.pinnedLimitRange
                )
            }

            Section("Drawer") {
                Toggle("Show floating pill when inactive", isOn: $settings.showFloatingPill)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Appear from")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    DrawerPositionGlassPicker(selection: $settings.preferredPosition)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 2)
                }
                .disabled(!settings.showFloatingPill)

                Text(settings.showFloatingPill
                     ? "The drawer collapses into a draggable pill. The menu bar icon always stays available."
                     : "The drawer hides when inactive. Left-click the menu bar icon to reopen it, or right-click for options.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Keyboard Shortcut") {
                ClipyShortcutRecorder(name: UserSettings.shortcutName)
                Text("Click the badge to record a new shortcut. The shortcut works from any app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
        .simultaneousGesture(
            TapGesture().onEnded {
                focusedLimitField = nil
            }
        )
        .contentMargins(.trailing, 2, for: .scrollIndicators)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Clipy Settings")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button {
                    isClearing = true
                } label: {
                    Text("Clear History")
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                }
                .tint(.red)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .clipShape(Capsule())

                Button {
                    isResetting = true
                } label: {
                    Text("Reset to Defaults")
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .overlay {
            if isClearing {
                ClipyFrostedConfirmationOverlay(
                    title: "Clear clipboard history?",
                    message: "This permanently deletes all saved clipboard items.",
                    confirmTitle: "Clear History",
                    checkboxLabel: "Also clear pinned items",
                    checkboxBinding: $clearIncludesPinned,
                    onConfirm: {
                        let includePinned = clearIncludesPinned
                        isClearing = false
                        clearIncludesPinned = false
                        Task { await onClearAll(includePinned) }
                    },
                    onCancel: {
                        isClearing = false
                        clearIncludesPinned = false
                    }
                )
                .transition(.opacity.combined(with: .scale(0.97)))
            } else if isResetting {
                ClipyFrostedConfirmationOverlay(
                    title: "Reset to defaults?",
                    message: "All settings will be restored to their original values.",
                    confirmTitle: "Reset",
                    onConfirm: {
                        isResetting = false
                        settings.resetToDefaults()
                        try? LaunchAtLoginService().setEnabled(false)
                    },
                    onCancel: { isResetting = false }
                )
                .transition(.opacity.combined(with: .scale(0.97)))
            }
        }
        .animation(.easeOut(duration: 0.22), value: isClearing)
        .animation(.easeOut(duration: 0.22), value: isResetting)
        .onChange(of: settings.historyLimitUnlimited) { _, _ in
            Task { await onLimitsChanged() }
        }
        .onChange(of: settings.historyLimitCount) { _, _ in
            Task { await onLimitsChanged() }
        }
        .onChange(of: settings.pinnedLimitUnlimited) { _, _ in
            Task { await onLimitsChanged() }
        }
        .onChange(of: settings.pinnedLimitCount) { _, _ in
            Task { await onLimitsChanged() }
        }
    }
}


private enum LimitField: Hashable {
    case history
    case pinned
}

private struct ItemLimitEditor: View {
    let field: LimitField
    var focusedField: FocusState<LimitField?>.Binding

    let title: String
    let caption: String
    @Binding var isUnlimited: Bool
    @Binding var count: Int
    let defaultCount: Int
    let range: ClosedRange<Int>

    @State private var countText = ""

    private var isFocused: Bool {
        focusedField.wrappedValue == field
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body)

            if !isUnlimited {
                HStack(spacing: 6) {
                    Text("Keep last")
                        .foregroundStyle(.secondary)

                    TextField("", text: $countText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .multilineTextAlignment(.trailing)
                        .focused(focusedField, equals: field)
                        .onSubmit(commitCountText)
                }

                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $isUnlimited) {
                Text("Unlimited")
                    .font(.subheadline.weight(.medium))
            }
            .toggleStyle(.switch)
        }
        .padding(.vertical, 2)
        .onAppear { syncCountText() }
        .onChange(of: count) { _, _ in
            guard !isFocused else { return }
            syncCountText()
        }
        .onChange(of: focusedField.wrappedValue) { oldValue, newValue in
            if oldValue == field, newValue != field {
                commitCountText()
            }
        }
        .onChange(of: isUnlimited) { _, unlimited in
            if unlimited {
                focusedField.wrappedValue = nil
            } else {
                syncCountText()
            }
        }
        .onChange(of: countText) { _, newValue in
            guard isFocused else { return }
            countText = sanitizedInput(newValue)
        }
    }

    private func syncCountText() {
        countText = String(count)
    }

    private func sanitizedInput(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        let capped = String(digits.prefix(3))
        guard let value = Int(capped), value > range.upperBound else { return capped }
        return String(range.upperBound)
    }

    private func commitCountText() {
        let trimmed = countText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            applyCount(defaultCount)
            return
        }

        guard let parsed = Int(trimmed), range.contains(parsed) else {
            applyCount(defaultCount)
            return
        }

        applyCount(parsed)
    }

    private func applyCount(_ value: Int) {
        count = value
        countText = String(value)
    }
}
