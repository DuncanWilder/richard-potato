import AppKit
import SwiftUI

@main
struct RichardPotatoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var controller = AppController.shared

    var body: some Scene {
        MenuBarExtra {
            if !controller.hotkeyActive {
                Text("Shortcut inactive — needs Accessibility permission")
                Button("Grant Accessibility access…") {
                    AccessibilityPermission.prompt()
                    AccessibilityPermission.openSettings()
                }
                Divider()
            }

            Button("Settings…") {
                SettingsWindowController.shared.show(controller: controller)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Analytics…") {
                AnalyticsWindowController.shared.show(controller: controller)
            }

            Button("Quit Richard Potato") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(nsImage: menuBarImage)
        }
    }

    private var menuBarImage: NSImage {
        switch controller.iconState {
        case .unavailable:
            return MenuBarIcon.silhouette
        case .ready:
            return MenuBarIcon.potato
        }
    }
}

enum MenuBarIconState {
    /// Accessibility or microphone permission is missing.
    case unavailable
    case ready
}

@MainActor
enum MenuBarIcon {
    /// Drawn as a template so the menu bar renders it as a flat white
    /// silhouette, matching how a plain `Text` label used to look.
    static let silhouette: NSImage = {
        let image = draw()
        image.isTemplate = true
        return image
    }()

    /// Non-template, so the emoji keeps its colour.
    static let potato: NSImage = {
        let image = draw()
        image.isTemplate = false
        return image
    }()

    private static func draw() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let glyph = "🥔" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14)
        ]

        return NSImage(size: size, flipped: false) { rect in
            let bounds = glyph.boundingRect(with: rect.size, options: [], attributes: attributes)
            glyph.draw(
                at: NSPoint(
                    x: rect.midX - bounds.width / 2,
                    y: rect.midY - bounds.height / 2
                ),
                withAttributes: attributes
            )
            return true
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppController.shared.start()
        }
    }
}
