import Foundation

extension Notification.Name {
    static let clipboardItemsDidChange    = Notification.Name("copydock.itemsDidChange")
    static let copydockDrawerPositionChanged = Notification.Name("copydock.drawerPositionChanged")
    static let copydockLimitsDidChange       = Notification.Name("copydock.limitsDidChange")
    static let openCopyDockDrawer            = Notification.Name("openCopyDockDrawer")
    static let openCopyDockSettings          = Notification.Name("openCopyDockSettings")
    static let closeCopyDockDrawer           = Notification.Name("copydock.closeDrawer")
    static let minimizeCopyDockDrawer        = Notification.Name("copydock.minimizeDrawer")
    static let copydockDrawerExpand          = Notification.Name("copydock.drawerExpand")
    static let copydockDrawerDidMinimize     = Notification.Name("copydock.drawerDidMinimize")
    static let copydockDrawerDidExpand       = Notification.Name("copydock.drawerDidExpand")
    static let copydockDrawerWillShow        = Notification.Name("copydock.drawerWillShow")
    static let copydockBlockAutoMinimize     = Notification.Name("copydock.blockAutoMinimize")
    static let copydockDrawerDragDidBegin    = Notification.Name("copydock.drawerDragDidBegin")
    static let copydockDrawerDragDidEnd      = Notification.Name("copydock.drawerDragDidEnd")
}
