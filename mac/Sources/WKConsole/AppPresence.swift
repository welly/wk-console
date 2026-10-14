import AppKit
import SwiftUI

/// Closing the window (⌘W) leaves WK Console running, connected, and showing the
/// speed in the menu bar. ⌘Q quits as usual. These bring the window back.
enum AppPresence {
    static let showMainWindow = Notification.Name("WKConsoleShowMainWindow")
    static let hideDockIconKey = "HideDockIconWhenClosed"

    private static func flag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    /// Called when the main window closes: with "Hide Dock icon" on (and the
    /// menu bar item shown, so there's still a way back), drop the Dock icon.
    static func windowClosed() {
        if flag(hideDockIconKey) && flag("ShowMenuBarItem") {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Put the Dock icon back, e.g. when the setting is turned off.
    static func showDockIcon() {
        NSApp.setActivationPolicy(.regular)
    }

    static func showApp(_ openWindow: OpenWindowAction) {
        showDockIcon()
        openWindow(id: "main")
        NSApp.activate()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// SwiftUI quits an app when its only window closes; WK Console keeps
    /// running in the menu bar instead. ⌘Q still quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon, or opening WK Console again from Finder, while
    /// its window is closed brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            NotificationCenter.default.post(name: AppPresence.showMainWindow, object: nil)
        }
        return true
    }
}
