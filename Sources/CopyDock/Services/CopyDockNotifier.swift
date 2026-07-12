import AppKit
import Foundation
import SwiftUI
import UserNotifications

@MainActor
enum CopyDockNotifier {

    static let successMessage = "Ready to paste"
    static let failureMessage = "Something went wrong"

    private static var configured = false
    private static let delegate = NotificationDelegate()
    private static var feedbackPanel: NSPanel?
    private static var feedbackHideTask: Task<Void, Never>?

    static func configure() {
        guard !configured else { return }
        configured = true
        UNUserNotificationCenter.current().delegate = delegate
    }

    static func requestPermissionIfNeeded() async -> Bool {
        configure()
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    static func notifyRestore(success: Bool, message: String) {
        let position = UserSettings.shared.preferredPosition
        showFeedbackPill(message: message, success: success, position: position)
        Task { await postSystemNotification(success: success, message: message) }
    }

    private static func showFeedbackPill(
        message: String,
        success: Bool,
        position: UserSettings.DrawerPosition
    ) {
        feedbackHideTask?.cancel()
        feedbackPanel?.orderOut(nil)

        let pill = FeedbackPill(message: message, success: success)
        let hosting = NSHostingView(rootView: pill)
        hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 40)

        let newPanel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.hasShadow = false
        newPanel.contentView = hosting
        newPanel.isReleasedWhenClosed = false

        positionFeedbackPanel(newPanel, at: position)
        newPanel.orderFront(nil)
        feedbackPanel = newPanel

        feedbackHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            feedbackPanel?.orderOut(nil)
            feedbackPanel = nil
        }
    }

    private static func positionFeedbackPanel(
        _ panel: NSPanel,
        at position: UserSettings.DrawerPosition
    ) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let sf = screen.visibleFrame
        let pad: CGFloat = 14
        let size = panel.frame.size

        let origin: CGPoint
        switch position {
        case .bottom:
            origin = CGPoint(x: sf.midX - size.width / 2, y: sf.minY + pad + 40)
        case .top:
            origin = CGPoint(x: sf.midX - size.width / 2, y: sf.maxY - size.height - pad - 40)
        }
        panel.setFrameOrigin(origin)
    }

    private static func postSystemNotification(success: Bool, message: String) async {
        configure()
        guard await requestPermissionIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = "CopyDock"
        content.body = message
        if success { content.sound = .default }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.01, repeats: false)
        let request = UNNotificationRequest(
            identifier: "copydock.restore.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}

private struct FeedbackPill: View {
    let message: String
    let success: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(success ? .green : .orange)
            Text(message)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}