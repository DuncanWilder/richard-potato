import AppKit
import SwiftUI

enum ListeningIndicatorState: Equatable {
    case recording
    case processing
}

/// A click-through panel that is visible only while dictation is active.
@MainActor
final class ListeningIndicatorController: ObservableObject {
    @Published private(set) var state: ListeningIndicatorState = .recording
    @Published private(set) var audioLevel: Double = 0

    private var panel: NSPanel?
    private var screenObserver: NSObjectProtocol?
    private var desiredState: ListeningIndicatorState?
    private var isVisible = false
    private var transitionID = 0

    func update(_ nextState: ListeningIndicatorState?, audioLevel: Double) {
        if self.audioLevel != audioLevel {
            self.audioLevel = audioLevel
        }
        guard nextState != desiredState else { return }
        desiredState = nextState
        transitionID += 1
        let currentTransition = transitionID

        guard let nextState else {
            guard let panel, isVisible else { return }
            isVisible = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self, weak panel] in
                MainActor.assumeIsolated {
                    guard let self, self.transitionID == currentTransition else { return }
                    panel?.orderOut(nil)
                }
            }
            return
        }

        let panel = makePanelIfNeeded()
        state = nextState
        guard !isVisible else { return }
        isVisible = true
        moveToPointerScreen()
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    func moveToPointerScreen() {
        guard let panel else { return }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.main
            ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: area.midX - panel.frame.width / 2,
            y: area.minY + 18
        ))
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 92, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: ListeningIndicatorView(model: self))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.panel = panel

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.moveToPointerScreen() }
        }
        return panel
    }
}

private struct ListeningIndicatorView: View {
    @ObservedObject var model: ListeningIndicatorController

    var body: some View {
        ZStack {
            levelBars
                .opacity(model.state == .recording ? 1 : 0)

            whiteSpinner
                .opacity(model.state == .processing ? 1 : 0)
        }
        .frame(width: 92, height: 38)
        .background(Color.black.opacity(0.84), in: Capsule())
        .padding(.vertical, 1)
        .animation(.easeInOut(duration: 0.18), value: model.state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.state == .recording ? "Dictation recording" : "Dictation finishing")
    }

    private var levelBars: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: model.state != .recording)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<9) { index in
                    let wave = abs(sin(time * 8 + Double(index) * 0.63))
                    let pattern = [0.4, 0.65, 0.85, 1.0, 0.9, 0.72, 0.55, 0.78, 0.45][index]
                    Capsule()
                        .fill(.white)
                        .frame(width: 3, height: 5 + model.audioLevel * (6 + wave * 12) * pattern)
                }
            }
        }
    }

    private var whiteSpinner: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: model.state != .processing)) { timeline in
            let angle = timeline.date.timeIntervalSinceReferenceDate * 300
            Circle()
                .trim(from: 0.08, to: 0.78)
                .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 18, height: 18)
                .rotationEffect(.degrees(angle.truncatingRemainder(dividingBy: 360)))
        }
    }
}
