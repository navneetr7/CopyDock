import Foundation
import KeyboardShortcuts

@Observable
final class UserSettings {
    @MainActor static let shared = UserSettings()

    var autoStart: Bool {
        didSet { UserDefaults.standard.set(autoStart, forKey: Keys.autoStart) }
    }

    var retentionDays: Int {
        didSet { UserDefaults.standard.set(retentionDays, forKey: Keys.retentionDays) }
    }

    var historyLimitUnlimited: Bool {
        didSet {
            UserDefaults.standard.set(historyLimitUnlimited, forKey: Keys.historyLimitUnlimited)
            notifyLimitsDidChange()
        }
    }

    var historyLimitCount: Int {
        didSet {
            let clamped = Self.clampHistoryCount(historyLimitCount)
            if clamped != historyLimitCount { historyLimitCount = clamped; return }
            UserDefaults.standard.set(historyLimitCount, forKey: Keys.historyLimitCount)
            notifyLimitsDidChange()
        }
    }

    var pinnedLimitUnlimited: Bool {
        didSet {
            UserDefaults.standard.set(pinnedLimitUnlimited, forKey: Keys.pinnedLimitUnlimited)
            notifyLimitsDidChange()
        }
    }

    var pinnedLimitCount: Int {
        didSet {
            let clamped = Self.clampPinnedCount(pinnedLimitCount)
            if clamped != pinnedLimitCount { pinnedLimitCount = clamped; return }
            UserDefaults.standard.set(pinnedLimitCount, forKey: Keys.pinnedLimitCount)
            notifyLimitsDidChange()
        }
    }

    var effectiveHistoryLimit: Int { historyLimitUnlimited ? 0 : historyLimitCount }
    var effectivePinnedLimit: Int  { pinnedLimitUnlimited  ? 0 : pinnedLimitCount  }

    static let defaultHistoryLimitCount = 100
    static let defaultPinnedLimitCount  = 50
    static let historyLimitRange = 1...999
    static let pinnedLimitRange  = 1...999

    var preferredPosition: DrawerPosition {
        didSet {
            UserDefaults.standard.set(preferredPosition.rawValue, forKey: Keys.preferredPosition)
            if oldValue != preferredPosition {
                clearWidgetCustomPosition()
                NotificationCenter.default.post(name: .clipyDrawerPositionChanged, object: nil)
            }
        }
    }

    var showFloatingPill: Bool {
        didSet {
            UserDefaults.standard.set(showFloatingPill, forKey: Keys.showFloatingPill)
            if !showFloatingPill {
                clearWidgetCustomPosition()
            }
            NotificationCenter.default.post(name: .clipyDrawerPositionChanged, object: nil)
        }
    }

    var widgetCustomOrigin: CGPoint? {
        didSet {
            let defaults = UserDefaults.standard
            if let origin = widgetCustomOrigin {
                defaults.set(origin.x, forKey: Keys.widgetOriginX)
                defaults.set(origin.y, forKey: Keys.widgetOriginY)
            } else {
                defaults.removeObject(forKey: Keys.widgetOriginX)
                defaults.removeObject(forKey: Keys.widgetOriginY)
            }
        }
    }

    var hasCustomWidgetPosition: Bool { widgetCustomOrigin != nil }

    static let shortcutName = KeyboardShortcuts.Name("openClipyDrawer")

    enum DrawerPosition: String, CaseIterable, Codable {
        case top, bottom

        var displayName: String {
            switch self {
            case .top:    return "Top"
            case .bottom: return "Bottom"
            }
        }
    }

    private enum Keys {
        static let autoStart             = "clipy.autoStart"
        static let retentionDays         = "clipy.retentionDays"
        static let historyLimitUnlimited = "clipy.historyLimitUnlimited"
        static let historyLimitCount     = "clipy.historyLimitCount"
        static let pinnedLimitUnlimited  = "clipy.pinnedLimitUnlimited"
        static let pinnedLimitCount      = "clipy.pinnedLimitCount"
        static let preferredPosition     = "clipy.preferredPosition"
        static let showFloatingPill      = "clipy.showFloatingPill"
        static let widgetOriginX         = "clipy.widgetOriginX"
        static let widgetOriginY         = "clipy.widgetOriginY"
    }

    private static func clampHistoryCount(_ value: Int) -> Int {
        min(max(value, historyLimitRange.lowerBound), historyLimitRange.upperBound)
    }

    private static func clampPinnedCount(_ value: Int) -> Int {
        min(max(value, pinnedLimitRange.lowerBound), pinnedLimitRange.upperBound)
    }

    private func notifyLimitsDidChange() {
        NotificationCenter.default.post(name: .clipyLimitsDidChange, object: nil)
    }

    func clearWidgetCustomPosition() { widgetCustomOrigin = nil }

    private init() {
        self.autoStart = UserDefaults.standard.bool(forKey: Keys.autoStart)

        let days = UserDefaults.standard.integer(forKey: Keys.retentionDays)
        self.retentionDays = days > 0 ? days : 30

        if UserDefaults.standard.object(forKey: Keys.historyLimitUnlimited) != nil {
            self.historyLimitUnlimited = UserDefaults.standard.bool(forKey: Keys.historyLimitUnlimited)
        } else {
            self.historyLimitUnlimited = false
        }

        let storedHistoryCount = UserDefaults.standard.integer(forKey: Keys.historyLimitCount)
        self.historyLimitCount = storedHistoryCount > 0
            ? Self.clampHistoryCount(storedHistoryCount)
            : Self.defaultHistoryLimitCount

        if UserDefaults.standard.object(forKey: Keys.pinnedLimitUnlimited) != nil {
            self.pinnedLimitUnlimited = UserDefaults.standard.bool(forKey: Keys.pinnedLimitUnlimited)
        } else {
            self.pinnedLimitUnlimited = false
        }

        let storedPinnedCount = UserDefaults.standard.integer(forKey: Keys.pinnedLimitCount)
        self.pinnedLimitCount = storedPinnedCount > 0
            ? Self.clampPinnedCount(storedPinnedCount)
            : Self.defaultPinnedLimitCount

        if let raw = UserDefaults.standard.string(forKey: Keys.preferredPosition),
           let pos = DrawerPosition(rawValue: raw) {
            self.preferredPosition = pos
        } else {
            self.preferredPosition = .bottom
        }

        if UserDefaults.standard.object(forKey: Keys.showFloatingPill) != nil {
            self.showFloatingPill = UserDefaults.standard.bool(forKey: Keys.showFloatingPill)
        } else {
            self.showFloatingPill = false
        }

        let wx = UserDefaults.standard.object(forKey: Keys.widgetOriginX) as? Double
        let wy = UserDefaults.standard.object(forKey: Keys.widgetOriginY) as? Double
        self.widgetCustomOrigin = (wx != nil && wy != nil) ? CGPoint(x: wx!, y: wy!) : nil

        if KeyboardShortcuts.getShortcut(for: Self.shortcutName) == nil {
            KeyboardShortcuts.setShortcut(.init(.v, modifiers: [.option, .shift]), for: Self.shortcutName)
        }
    }

    func resetToDefaults() {
        autoStart = false
        retentionDays = 30
        historyLimitUnlimited = false
        historyLimitCount = Self.defaultHistoryLimitCount
        pinnedLimitUnlimited = false
        pinnedLimitCount = Self.defaultPinnedLimitCount
        preferredPosition = .bottom
        showFloatingPill = false
        clearWidgetCustomPosition()
        KeyboardShortcuts.setShortcut(.init(.v, modifiers: [.option, .shift]), for: Self.shortcutName)
    }
}
