import SwiftUI
import AppKit
import Carbon
import KeyboardShortcuts

@Observable
@MainActor
private final class RecorderState {
    var isRecording = false
    var shortcut: KeyboardShortcuts.Shortcut?
    private var monitor: Any?

    let name: KeyboardShortcuts.Name

    init(name: KeyboardShortcuts.Name) {
        self.name = name
        self.shortcut = KeyboardShortcuts.getShortcut(for: name)
    }

    func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    func clear() {
        KeyboardShortcuts.setShortcut(nil, for: name)
        shortcut = nil
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { stopRecording(); return } // Escape cancels
        guard !event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return }
        if let s = KeyboardShortcuts.Shortcut(event: event) {
            KeyboardShortcuts.setShortcut(s, for: name)
            shortcut = s
        }
        stopRecording()
    }

    var displayText: String {
        guard let shortcut else { return "Record shortcut" }
        return formatShortcut(shortcut)
    }

    private func formatShortcut(_ s: KeyboardShortcuts.Shortcut) -> String {
        var text = ""
        if s.modifiers.contains(.control) { text += "⌃" }
        if s.modifiers.contains(.option)  { text += "⌥" }
        if s.modifiers.contains(.shift)   { text += "⇧" }
        if s.modifiers.contains(.command) { text += "⌘" }
        if let key = s.key {
            text += keyLabel(carbonKeyCode: key.rawValue)
        }
        return text
    }

    private func keyLabel(carbonKeyCode: Int) -> String {
        let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        guard let src,
              let layoutData = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue()
        let layoutPtr = CFDataGetBytePtr(data).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { $0 }
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        UCKeyTranslate(layoutPtr, UInt16(carbonKeyCode), UInt16(kUCKeyActionDisplay),
                       0, UInt32(LMGetKbdType()),
                       OptionBits(kUCKeyTranslateNoDeadKeysBit),
                       &deadKeyState, 4, &length, &chars)
        let str = String(chars[0..<length].compactMap { $0 > 0 ? Character(Unicode.Scalar($0)!) : nil })
        return str.isEmpty ? "?" : str.uppercased()
    }
}

struct ClipyShortcutRecorder: View {
    let name: KeyboardShortcuts.Name

    @State private var state: RecorderState

    init(name: KeyboardShortcuts.Name) {
        _state = State(initialValue: RecorderState(name: name))
    }

    var body: some View {
        HStack(spacing: 8) {
            badge
            if state.shortcut != nil, !state.isRecording {
                Button("Clear") { state.clear() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            if state.isRecording {
                Button("Cancel") { state.stopRecording() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .onDisappear { state.stopRecording() }
    }

    private var badge: some View {
        Text(state.isRecording ? "Type shortcut…" : state.displayText)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(state.isRecording ? Color.accentColor : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(state.isRecording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        state.isRecording ? Color.accentColor : Color.primary.opacity(0.2),
                        lineWidth: state.isRecording ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if state.isRecording { state.stopRecording() } else { state.startRecording() }
            }
    }
}
