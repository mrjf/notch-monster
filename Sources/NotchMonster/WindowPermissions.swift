import ApplicationServices
import Observation
import OSLog
import ScreenCaptureKit

@MainActor
@Observable
final class WindowPermissions {
    enum ScreenRecordingAccess {
        case unverified, granted, denied
    }

    private(set) var accessibilityGranted = false
    private(set) var screenRecordingAccess = ScreenRecordingAccess.unverified
    var screenRecordingGranted: Bool { screenRecordingAccess == .granted }
    private(set) var checking = false
    private(set) var captureError: String?
    var ready: Bool { accessibilityGranted && screenRecordingGranted }

    @ObservationIgnored private let readAccessibility: () -> Bool
    @ObservationIgnored private let probeCapture: () async throws -> Void
    @ObservationIgnored private let logger = Logger(subsystem: "com.notchmonster.app", category: "Permissions")

    init(readAccessibility: @escaping () -> Bool = { AXIsProcessTrusted() },
         probeCapture: @escaping () async throws -> Void = WindowPermissions.verifyCapture) {
        self.readAccessibility = readAccessibility
        self.probeCapture = probeCapture
    }

    func refreshAccessibility() {
        accessibilityGranted = readAccessibility()
    }

    func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        refreshAccessibility()
        do {
            try await probeCapture()
            captureSucceeded()
        } catch {
            captureFailed(error)
        }
        refreshAccessibility()
        logger.notice("CHECK accessibility=\(self.accessibilityGranted) capture=\(self.screenRecordingGranted)")
    }

    func captureSucceeded() {
        screenRecordingAccess = .granted
        captureError = nil
    }

    func captureFailed(_ error: Error) {
        let error = error as NSError
        if error.domain == SCStreamErrorDomain && error.code == SCStreamError.Code.userDeclined.rawValue {
            screenRecordingAccess = .denied
        } else if !screenRecordingGranted {
            screenRecordingAccess = .unverified
        }
        captureError = "\(error.localizedDescription) (\(error.domain), \(error.code))"
        logger.error("CAPTURE unavailable: \(self.captureError ?? "", privacy: .public)")
    }

    private static func verifyCapture() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw CaptureCheckError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        // Exercise the capture API without retaining a desktop image.
        config.sourceRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        config.width = 1
        config.height = 1
        config.showsCursor = false
        _ = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private enum CaptureCheckError: LocalizedError {
        case noDisplay
        var errorDescription: String? { "No display is available for the capture check." }
    }
}
