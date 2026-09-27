import AppKit
import SwiftUI

/// Hosts the analytics UI in a window we own, matching Settings.
@MainActor
final class AnalyticsWindowController: NSObject, NSWindowDelegate {
    static let shared = AnalyticsWindowController()

    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible == true }

    func show(controller: AppController) {
        NSApp.setActivationPolicy(.regular)

        if window == nil {
            let hosting = NSHostingController(
                rootView: AnalyticsView(analytics: controller.analytics)
                    .environmentObject(controller)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = "Richard Potato Analytics"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 560, height: 680))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Drop back to accessory unless Settings is still open.
        if SettingsWindowController.shared.isVisible { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
