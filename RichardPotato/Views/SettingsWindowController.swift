import AppKit
import SwiftUI

/// Hosts the settings UI in a window we own.
///
/// SwiftUI's `Settings` scene and `SettingsLink` are unreliable in a menu bar
/// only (`LSUIElement`) app: nothing activates the app first, so the window can
/// fail to appear at all. Owning the window keeps the behaviour predictable.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = SettingsWindowController()

    enum Page: String, CaseIterable, Identifiable {
        case settings
        case corrections
        case analytics

        var id: Self { self }

        var title: String {
            switch self {
            case .settings: return "Settings"
            case .corrections: return "Custom corrections"
            case .analytics: return "Analytics"
            }
        }

        var systemImage: String {
            switch self {
            case .settings: return "gearshape"
            case .corrections: return "text.badge.checkmark"
            case .analytics: return "chart.bar"
            }
        }
    }

    @Published var selectedPage: Page = .settings
    private var window: NSWindow?

    func show(controller: AppController, page: Page = .settings) {
        selectedPage = page
        // A menu bar app is an accessory app, which cannot own a key window.
        NSApp.setActivationPolicy(.regular)

        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Richard Potato settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbar = nil
            window.minSize = NSSize(width: 700, height: 520)
            window.collectionBehavior = [.moveToActiveSpace]
            if !window.setFrameUsingName("RichardPotatoSettingsWindow") {
                window.center()
            }
            window.setFrameAutosaveName("RichardPotatoSettingsWindow")
            window.contentView = NSHostingView(
                rootView: SettingsWindowView(navigation: self)
                    .environmentObject(controller)
            )
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }

        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFrontRegardless()
        window?.makeMain()
        window?.makeKeyAndOrderFront(nil)

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
        window = nil
        // Drop back to accessory so the app keeps no Dock icon.
        NSApp.setActivationPolicy(.accessory)
    }
}

struct SettingsWindowView: View {
    @EnvironmentObject private var controller: AppController
    @ObservedObject var navigation: SettingsWindowController
    @ViewState private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                Text(navigation.selectedPage.title)
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 22)
                    .padding(.bottom, 8)

                switch navigation.selectedPage {
                case .settings:
                    SettingsView()
                case .corrections:
                    CustomCorrectionsView()
                case .analytics:
                    AnalyticsView(analytics: controller.analytics)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 700, minHeight: 520)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(
                selection: Binding<SettingsWindowController.Page?>(
                    get: { navigation.selectedPage },
                    set: { if let page = $0 { navigation.selectedPage = page } }
                )
            ) {
                Section("Richard Potato") {
                    ForEach(SettingsWindowController.Page.allCases) { page in
                        Label(page.title, systemImage: page.systemImage)
                            .tag(page)
                    }
                }
            }
            .listStyle(.sidebar)

            Text(
                "Richard Potato \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}
