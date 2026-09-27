import Foundation
import FoundationModels

enum TranscriptRefiner {
    static func refine(_ transcript: String) async -> String {
        guard SystemLanguageModel.default.isAvailable else {
            Log.dictation.error("Transcript refinement unavailable; using original text")
            return transcript
        }

        let session = LanguageModelSession(instructions: """
            You are a copy editor for speech transcripts. Edit the supplied text, \
            not the ideas in it. Remove only filler words such as um and uh, \
            repeated words, and clear false starts. Correct capitalization, \
            punctuation, and obvious grammar errors. Keep every question as a \
            question. Preserve the speaker's meaning, names, facts, and wording \
            as closely as possible. Do not answer questions, summarize, explain, \
            infer intent, or add information. Return only the edited transcript.
            """)
        do {
            let response = try await session.respond(to: transcript)
            let result = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isConservativeEdit(result, of: transcript) else {
                Log.dictation.error("Transcript refinement changed too much; using original text")
                return transcript
            }
            return result
        } catch {
            Log.dictation.error("Transcript refinement failed: \(error.localizedDescription, privacy: .public)")
            return transcript
        }
    }

    /// A small local check catches answers and large rewrites. It cannot prove
    /// that every edit is correct, so a doubtful result keeps the original.
    private static func isConservativeEdit(_ result: String, of original: String) -> Bool {
        guard !result.isEmpty else { return false }
        if original.contains("?") && !result.contains("?") { return false }

        let source = words(in: original)
        let edited = words(in: result)
        guard !source.isEmpty, !edited.isEmpty else { return false }
        if edited.count > source.count + max(4, source.count / 4) { return false }

        let sourceWords = Set(source)
        let newWords = edited.filter { !sourceWords.contains($0) }
        return newWords.count <= max(3, edited.count / 4)
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
