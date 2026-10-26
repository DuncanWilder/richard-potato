import Testing

@testable import RichardPotato

@Suite("Capture session")
struct CaptureSessionTests {
    @Test("Ignore text outside an active capture")
    func ignoreInactiveText() {
        var session = CaptureSession()
        session.ingest(text: "Ignored", isVolatile: false)
        #expect(session.displayedText.isEmpty)
    }

    @Test("Replace provisional text and commit the final transcript")
    func commitTranscript() {
        var session = CaptureSession()
        session.begin()
        session.ingest(text: " Wrong", isVolatile: true)
        session.ingest(text: " Hello", isVolatile: false)
        session.ingest(text: " world ", isVolatile: true)
        #expect(session.displayedText == " Hello world ")
        #expect(session.end() == "Hello world")
        #expect(!session.isActive)
        #expect(session.volatile.isEmpty)
        session.begin()
        #expect(session.displayedText.isEmpty)
    }
}
