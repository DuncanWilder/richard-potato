import AppKit
import SwiftUI

/// Hosts the settings UI in a window we own.
///
/// SwiftUI's `Settings` scene and `SettingsLink` are unreliable in a menu bar
/// only (`LSUIElement`) app: nothing activates the app first, so the window can
/// fail to appear at all. Owning the window keeps the behaviour predictable.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible == true }

    func show(controller: AppController) {
        // A menu bar app is an accessory app, which cannot own a key window.
        NSApp.setActivationPolicy(.regular)

        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView().environmentObject(controller)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = "Richard Potato Settings"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 560, height: 440))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            Log.hotkey.info(
                """
                Settings window shown: visible=\(window.isVisible, privacy: .public) \
                key=\(window.isKeyWindow, privacy: .public) \
                frame=\(NSStringFromRect(window.frame), privacy: .public) \
                policy=\(NSApp.activationPolicy().rawValue, privacy: .public)
                """
            )
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Drop back to accessory so the app keeps no Dock icon, unless Analytics
        // is still open.
        if AnalyticsWindowController.shared.isVisible { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
