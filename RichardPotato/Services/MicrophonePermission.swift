import AVFoundation
import Foundation

enum MicrophonePermission {
    enum Status {
        case granted
        case denied
        case undetermined

        var isGranted: Bool { self == .granted }

        var description: String {
            switch self {
            case .granted: return "Granted"
            case .denied: return "Denied"
            case .undetermined: return "Not requested"
            }
        }
    }

    /// Reads the current state without ever showing a prompt.
    static var status: Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .notDetermined:
            return .undetermined
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    /// Only shows the system prompt when the user has never been asked.
    @discardableResult
    static func requestIfNeeded() async -> Status {
        guard status == .undetermined else { return status }
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        return status
    }
}
