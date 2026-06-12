import Foundation

extension Notification.Name {
    static let clipboardItemsDidChange    = Notification.Name("clipy.itemsDidChange")
    static let clipyDrawerPositionChanged = Notification.Name("clipy.drawerPositionChanged")
    static let clipyLimitsDidChange       = Notification.Name("clipy.limitsDidChange")
    static let openClipySettings          = Notification.Name("openClipySettings")
    static let closeClipyDrawer           = Notification.Name("clipy.closeDrawer")
    static let minimizeClipyDrawer        = Notification.Name("clipy.minimizeDrawer")
    static let clipyDrawerExpand          = Notification.Name("clipy.drawerExpand")
    static let clipyDrawerDidMinimize     = Notification.Name("clipy.drawerDidMinimize")
    static let clipyDrawerDidExpand       = Notification.Name("clipy.drawerDidExpand")
    static let clipyDrawerWillShow        = Notification.Name("clipy.drawerWillShow")
    static let clipyBlockAutoMinimize     = Notification.Name("clipy.blockAutoMinimize")
    static let clipyDrawerDragDidBegin    = Notification.Name("clipy.drawerDragDidBegin")
    static let clipyDrawerDragDidEnd      = Notification.Name("clipy.drawerDragDidEnd")
}
