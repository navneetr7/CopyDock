import AppKit
import ApplicationServices

/// Sends ⌘V to the app that was frontmost before the drawer opened.
/// Requires the user to grant Accessibility permission; callers fall back
/// to copy-only when `isTrusted` is false.
@MainActor
enum Paster {

    private(set) static var targetApp: NSRunningApplication?

    /// Remembers the frontmost app every time the drawer is about to show.
    static func install() {
        NotificationCenter.default.addObserver(
            forName: .copydockDrawerWillShow, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                if let app = NSWorkspace.shared.frontmostApplication,
                   app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    targetApp = app
                }
            }
        }
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt if permission was never granted.
    @discardableResult
    static func requestAccess() -> Bool {
        // kAXTrustedCheckOptionPrompt isn't concurrency-safe under Swift 6; the key is a stable constant.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func pasteIntoTargetApp() {
        guard isTrusted else { return }
        targetApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            sendCmdV()
        }
    }

    private static func sendCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
