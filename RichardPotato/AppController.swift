import AVFoundation
import AppKit
import Combine
import SwiftUI

@MainActor
final class AppController: ObservableObject {
    static let shared = AppController()

    let engine = DictationEngine()
    let store = PreferencesStore()
    let analytics = AnalyticsStore.shared

    @Published var microphoneStatus = MicrophonePermission.status
    @Published var hotkeyActive = false
    @Published private(set) var isFinishingDictation = false

    var microphoneGranted: Bool { microphoneStatus.isGranted }

    var iconState: MenuBarIconState {
        if !hotkeyActive || !microphoneGranted { return .unavailable }
        return .ready
    }

    private let hotkey = HotkeyMonitor()
    private let live = LiveTextStream()
    private let listeningIndicator = ListeningIndicatorController()
    private var cancellables: Set<AnyCancellable> = []
    private var pipeline: Task<Void, Never>?
    private var didStart = false
    /// Wall-clock start of the active mic-open capture, for analytics.
    private var captureStartedAt: Date?

    init() {
        hotkey.onPress = { [weak self] in
            self?.handlePress()
        }
        hotkey.onRelease = { [weak self] in
            self?.handleRelease()
        }
        hotkey.onTapStateChange = { [weak self] installed in
            self?.hotkeyActive = installed
        }

        engine.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.streamTranscript()
                self?.syncListeningIndicator()
            }
            .store(in: &cancellables)

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.syncHotkey()
            }
            .store(in: &cancellables)

        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.store.record(event) else { return event }
            return nil
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            _ = self?.store.record(event)
        }
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        Log.hotkey.info("Controller starting; shortcut: \(self.store.shortcut.displayName, privacy: .public)")

        if !AccessibilityPermission.isGranted {
            Log.hotkey.error("Accessibility permission missing; shortcut inactive")
        }

        syncHotkey()
        syncListeningIndicator()
        hotkey.start()
        Task {
            await requestMicrophoneIfNeeded()
            await engine.prepare(microphoneUID: store.microphoneUID)
        }
    }

    /// Reads permission state without prompting. Safe to call on every appearance.
    func refreshPermissions() {
        microphoneStatus = MicrophonePermission.status
        hotkeyActive = hotkey.isTapInstalled
    }

    func requestMicrophoneIfNeeded() async {
        microphoneStatus = await MicrophonePermission.requestIfNeeded()
        hotkeyActive = hotkey.isTapInstalled
    }

    func selectMicrophone(uid: String?) {
        store.microphoneUID = uid
        store.save()
        Task {
            await engine.prepare(microphoneUID: uid)
        }
    }

    func setListeningIndicatorVisible(_ visible: Bool) {
        store.showListeningIndicator = visible
        store.save()
        syncListeningIndicator()
    }

    var isCapturing: Bool { engine.isCapturing }

    func handlePress() {
        if store.isRecording { return }
        Log.hotkey.info("Handling press in \(self.store.activationMode.rawValue) mode")
        switch store.activationMode {
        case .hold:
            startDictation()
        case .toggle:
            if engine.isCapturing {
                stopDictation()
            } else {
                startDictation()
            }
        }
    }

    func handleRelease() {
        guard store.activationMode == .hold else { return }
        stopDictation()
    }

    func startDictation() {
        // Starting again should not wait out the previous dictation's tail.
        engine.endTailEarly()
        enqueue { [self] in
            guard !engine.isCapturing else { return }
            Log.dictation.info("Starting capture (engine ready: \(self.engine.isReady))")
            if store.insertionMethod == .typing {
                live.begin()
            }
            captureStartedAt = Date()
            engine.beginCapture()
            listeningIndicator.moveToPointerScreen()
            syncListeningIndicator()
        }
    }

    func stopDictation() {
        enqueue { [self] in
            guard engine.isCapturing else { return }
            isFinishingDictation = true
            syncListeningIndicator()
            let text = store.correct(await engine.endCapture())
            let endedAt = Date()
            if let startedAt = captureStartedAt {
                analytics.record(startedAt: startedAt, endedAt: endedAt, transcript: text)
                captureStartedAt = nil
            }
            Log.dictation.info("Stopped capture; \(text.count) characters")
            switch store.insertionMethod {
            case .typing:
                // Streamed while speaking; this settles the finalised tail.
                live.finish(with: text)
            case .paste:
                if store.postProcessTranscript && !text.isEmpty {
                    let refined = await TranscriptRefiner.refine(text)
                    TextInserter.insert(refined, using: .paste)
                } else {
                    TextInserter.insert(text, using: .paste)
                }
            }
            // Still inside the queued work, so the next press waits for it.
            await engine.prepareForNextCapture()
            isFinishingDictation = false
            syncListeningIndicator()
        }
    }

    /// Runs capture transitions one after another. Finalising a dictation is
    /// asynchronous, and starting the next one before it completes is what
    /// makes the previous transcript reappear.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = pipeline
        pipeline = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    private func syncHotkey() {
        hotkey.update(shortcut: store.shortcut, paused: store.isRecording)
    }

    private func syncListeningIndicator() {
        guard store.showListeningIndicator else {
            listeningIndicator.update(nil, audioLevel: 0)
            return
        }
        if isFinishingDictation {
            listeningIndicator.update(.processing, audioLevel: 0)
        } else if engine.isCapturing && engine.isListening {
            listeningIndicator.update(.recording, audioLevel: engine.audioLevel)
        } else {
            listeningIndicator.update(nil, audioLevel: 0)
        }
    }

    private func streamTranscript() {
        // Keyed to the live stream rather than `isCapturing` so words spoken
        // into the tail keep appearing after the key is released.
        guard store.insertionMethod == .typing, live.isActive else { return }
        live.update(to: store.correct(engine.displayedText))
    }
}
