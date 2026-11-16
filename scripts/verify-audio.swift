import AVFoundation
import Foundation
import Speech

/// Local verification only. Reads a file without opening a microphone or audio output.
@main
struct VerifyAudio {
    static func main() async {
        do {
            try await verify()
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func verify() async throws {
        guard CommandLine.arguments.count == 4 else {
            throw NSError(
                domain: "VerifyAudio", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Expected audio-file, expected-text, and locale."
                ])
        }
        let arguments = CommandLine.arguments
        guard SpeechTranscriber.isAvailable,
            let locale = await SpeechTranscriber.supportedLocale(
                equivalentTo: Locale(identifier: arguments[3]))
        else {
            throw NSError(
                domain: "VerifyAudio", code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "On-device speech or the requested locale is unavailable."
                ])
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let modelStatus = await AssetInventory.status(forModules: [transcriber])
        print("Speech model status: \(modelStatus)")
        switch modelStatus {
        case .installed:
            break
        case .supported, .downloading:
            guard
                let request = try await AssetInventory.assetInstallationRequest(
                    supporting: [transcriber])
            else {
                throw NSError(
                    domain: "VerifyAudio", code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Speech model unavailable. Complete setup in the app."
                    ])
            }
            print("Preparing the on-device speech model; network access can be required.")
            try await request.downloadAndInstall()
        case .unsupported:
            throw NSError(
                domain: "VerifyAudio", code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "The speech model is unsupported."
                ])
        @unknown default:
            throw NSError(domain: "VerifyAudio", code: 2)
        }
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: arguments[1]))
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let results = Task { () throws -> String in
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }
        defer { results.cancel() }
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        let text = try await results.value
        func normalized(_ value: String) -> String {
            value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .joined(separator: " ")
        }
        guard !normalized(arguments[2]).isEmpty,
            normalized(text) == normalized(arguments[2])
        else {
            throw NSError(
                domain: "VerifyAudio", code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Transcript mismatch. Recognized: \(text)"
                ])
        }
        print("PASS: silent file recognition matched the expected text: \(text)")
    }
}
