import AVFoundation
import Foundation
import Speech

enum DictationEngineError: LocalizedError {
    case speechUnavailable
    case microphoneDenied
    case noMicrophoneFormat
    case modelMissing
    case converterFailed
    case analyzerFormatUnavailable

    var errorDescription: String? {
        switch self {
        case .speechUnavailable:
            return "On-device speech transcription is not available on this Mac."
        case .microphoneDenied:
            return "Microphone access is required for dictation."
        case .noMicrophoneFormat:
            return "No microphone input is available."
        case .modelMissing:
            return "The on-device speech model is not installed yet."
        case .converterFailed:
            return "Could not convert microphone audio for dictation."
        case .analyzerFormatUnavailable:
            return "Could not negotiate an on-device dictation audio format."
        }
    }
}

/// Keeps the microphone, SpeechAnalyzer, and on-device model warm so a hotkey
/// only flips capture on. Built-in keyboard dictation is not used because it
/// cold-starts too slowly.
@MainActor
final class DictationEngine: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var isCapturing = false
    /// True whenever the microphone is actually open, which includes the tail
    /// recorded after the key is released.
    @Published private(set) var isListening = false
    @Published private(set) var status = "Starting…"
    @Published private(set) var displayedText = ""
    @Published private(set) var audioLevel: Double = 0
    @Published private(set) var lastError: String?
    @Published private(set) var inputDevices: [AudioInputDevice] = []

    /// Created per capture. Holding an `AVAudioEngine` with a live input node
    /// keeps the HAL input unit initialised, which is what lights the system's
    /// orange microphone indicator, so the mic is only opened while dictating.
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var session = CaptureSession()
    private var analysisFormat: AVAudioFormat?
    private var tailTask: Task<Void, Never>?
    private var locale: Locale = .current

    /// How long the microphone keeps listening after the key is released.
    private static let tailDuration: Duration = .seconds(1)
    private var microphoneUID: String?
    private let deviceObserver = AudioInputDeviceObserver()

    init() {
        inputDevices = AudioInputDevices.available()
        deviceObserver.start { [weak self] in
            Task { @MainActor in self?.refreshInputDevices() }
        }
    }

    func refreshInputDevices() {
        inputDevices = AudioInputDevices.available()
    }

    func prepare(microphoneUID: String?) async {
        self.microphoneUID = microphoneUID
        refreshInputDevices()
        do {
            try await warmUp()
            isReady = true
            lastError = nil
            status = "Ready"
        } catch {
            isReady = false
            lastError = error.localizedDescription
            status = error.localizedDescription
        }
    }

    func beginCapture() {
        startAudio()
        session.begin()
        isCapturing = true
        displayedText = ""
        if isReady {
            status = "Listening…"
        }
    }

    func endCapture() async -> String {
        // Reported early so the UI settles and a new press is never dropped
        // while the tail of this dictation is still being captured.
        isCapturing = false
        await recordTail()
        stopAudio()
        await flushPendingResults()
        let text = session.end()
        displayedText = text
        status = isReady ? "Ready" : status
        return text
    }

    /// Keeps the microphone open briefly after the key is released, because a
    /// word still being spoken at that moment would otherwise be cut off.
    private func recordTail() async {
        guard engine != nil else { return }
        let task = Task<Void, Never> {
            _ = try? await Task.sleep(for: Self.tailDuration)
        }
        tailTask = task
        await task.value
        tailTask = nil
    }

    /// Abandons the tail when the user starts another dictation straight away.
    func endTailEarly() {
        tailTask?.cancel()
    }

    /// Releasing the key does not mean the recogniser is finished: audio that
    /// was already captured is still being analysed. Finalising flushes those
    /// results into the session that produced them, so they are neither lost
    /// nor replayed at the start of the next dictation.
    private func flushPendingResults() async {
        guard let analyzer else { return }
        let started = CFAbsoluteTimeGetCurrent()
        let before = session.displayedText.count

        do {
            try await analyzer.finalize(through: nil)
        } catch {
            Log.dictation.error("Finalize failed: \(error.localizedDescription, privacy: .public)")
        }

        // Let the results task deliver whatever finalizing emitted.
        for _ in 0..<4 {
            await Task.yield()
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
        let gained = session.displayedText.count - before
        Log.dictation.info(
            "Finalized in \(elapsed, format: .fixed(precision: 1), privacy: .public)ms, recovered \(gained, privacy: .public) chars"
        )
    }

    /// Opens the microphone. Everything expensive (model, analyzer) is already
    /// warm, so this is the only work a hotkey press pays for.
    private func startAudio() {
        guard engine == nil, let analysisFormat, let inputContinuation else { return }
        let started = CFAbsoluteTimeGetCurrent()
        var lastLevelUpdate: CFAbsoluteTime = 0

        let engine = AVAudioEngine()
        AudioInputDevices.apply(uid: microphoneUID, to: engine)

        let input = engine.inputNode
        let naturalFormat = input.outputFormat(forBus: 0)
        guard naturalFormat.sampleRate > 0, naturalFormat.channelCount > 0 else {
            lastError = DictationEngineError.noMicrophoneFormat.localizedDescription
            return
        }

        let converter: AudioBufferConverter?
        if audioFormatsMatch(naturalFormat, analysisFormat) {
            converter = nil
        } else {
            converter = AudioBufferConverter(inputFormat: naturalFormat, outputFormat: analysisFormat)
            guard converter != nil else {
                lastError = DictationEngineError.converterFailed.localizedDescription
                return
            }
        }

        input.installTap(onBus: 0, bufferSize: 512, format: naturalFormat) { [weak self] buffer, _ in
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastLevelUpdate >= 1.0 / 15.0 {
                lastLevelUpdate = now
                let level = DictationEngine.meterLevel(for: buffer)
                DispatchQueue.main.async { [weak self] in
                    self?.audioLevel = level
                }
            }
            let converted = converter?.convert(buffer) ?? copyPCMBuffer(buffer)
            guard let converted else { return }
            inputContinuation.yield(AnalyzerInput(buffer: converted))
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            lastError = error.localizedDescription
            status = error.localizedDescription
            return
        }

        self.engine = engine
        isListening = true
        let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
        Log.dictation.info("Microphone opened in \(elapsed, format: .fixed(precision: 1), privacy: .public)ms")
    }

    /// Releases the microphone so the system indicator clears between dictations.
    private func stopAudio() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
        self.engine = nil
        isListening = false
        audioLevel = 0
    }

    /// Maps microphone RMS to a visible level without keeping audio samples.
    private nonisolated static func meterLevel(for buffer: AVAudioPCMBuffer) -> Double {
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum = 0.0
        if let samples = buffer.floatChannelData?[0] {
            for index in 0..<count {
                let sample = Double(samples[index])
                sum += sample * sample
            }
        } else if let samples = buffer.int16ChannelData?[0] {
            for index in 0..<count {
                let sample = Double(samples[index]) / Double(Int16.max)
                sum += sample * sample
            }
        } else {
            return 0
        }
        let rms = sqrt(sum / Double(count))
        let decibels = 20 * log10(max(rms, 0.000_001))
        return min(1, max(0, (decibels + 50) / 38))
    }

    func installModelIfNeeded() async {
        do {
            try await ensureModel(for: locale)
            await prepare(microphoneUID: microphoneUID)
        } catch {
            lastError = error.localizedDescription
            status = error.localizedDescription
        }
    }

    /// Gives the next dictation a fresh transcriber. Reusing one carries the
    /// previous utterance's context over, which corrupts the start of the next
    /// transcript. The model is already loaded, so this is cheap, and it runs
    /// while the user is idle rather than on the hotkey path.
    func prepareForNextCapture() async {
        guard isReady else { return }
        let started = CFAbsoluteTimeGetCurrent()
        do {
            try await buildAnalyzer()
            let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
            Log.dictation.info(
                "Analyzer rebuilt in \(elapsed, format: .fixed(precision: 1), privacy: .public)ms"
            )
        } catch {
            isReady = false
            lastError = error.localizedDescription
            status = error.localizedDescription
        }
    }

    private func warmUp() async throws {
        guard SpeechTranscriber.isAvailable else { throw DictationEngineError.speechUnavailable }
        try await requestMicrophone()

        locale = await resolvedLocale()
        try await ensureModel(for: locale)

        try await buildAnalyzer()
    }

    private func buildAnalyzer() async throws {
        teardown()

        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        guard let analysisFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            throw DictationEngineError.analyzerFormatUnavailable
        }

        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .lingering)
        )
        try await analyzer.prepareToAnalyze(in: analysisFormat)

        // The analyzer consumes this stream for the app's lifetime; it simply
        // receives no buffers while the microphone is closed.
        let (stream, continuation) = AsyncStream.makeStream(
            of: AnalyzerInput.self,
            bufferingPolicy: .bufferingNewest(8)
        )

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.analysisFormat = analysisFormat
        self.inputContinuation = continuation

        analysisTask = Task { [weak self] in
            do {
                try await analyzer.start(inputSequence: stream)
            } catch is CancellationError {
                return
            } catch {
                self?.lastError = error.localizedDescription
                self?.status = error.localizedDescription
                self?.isReady = false
            }
        }

        resultTask = Task { [weak self, transcriber] in
            do {
                for try await result in transcriber.results {
                    self?.ingest(result)
                }
            } catch is CancellationError {
                return
            } catch {
                self?.lastError = error.localizedDescription
            }
        }

        status = "Ready"
    }

    private func teardown() {
        stopAudio()
        resultTask?.cancel()
        analysisTask?.cancel()
        resultTask = nil
        analysisTask = nil
        inputContinuation?.finish()
        inputContinuation = nil
        analyzer = nil
        transcriber = nil
        analysisFormat = nil
    }

    private func ingest(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters)
        session.ingest(text: text, isVolatile: !result.isFinal)
        if session.isActive {
            displayedText = session.displayedText
        }
    }

    private func resolvedLocale() async -> Locale {
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            return match
        }
        return Locale(identifier: "en_US")
    }

    private func ensureModel(for locale: Locale) async throws {
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            _ = try? await AssetInventory.reserve(locale: locale)
        case .supported, .downloading:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                status = "Installing on-device speech model…"
                try await request.downloadAndInstall()
                _ = try? await AssetInventory.reserve(locale: locale)
            } else {
                throw DictationEngineError.modelMissing
            }
        case .unsupported:
            throw DictationEngineError.speechUnavailable
        @unknown default:
            throw DictationEngineError.modelMissing
        }
    }

    private func requestMicrophone() async throws {
        if await MicrophonePermission.requestIfNeeded() != .granted {
            throw DictationEngineError.microphoneDenied
        }
    }
}
