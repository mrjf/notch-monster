import AppKit
import ScreenCaptureKit

@MainActor
enum WindowSnapshot {
    enum CaptureError: LocalizedError {
        case windowNotFound
        var errorDescription: String? {
            switch self {
            case .windowNotFound: "The dragged window could not be captured."
            }
        }
    }

    static func capture(pid: pid_t, bounds: CGRect, title: String?) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        // Match the captured window, never whichever window happens to be front.
        let candidates = content.windows.filter {
            $0.owningApplication?.processID == pid &&
            abs($0.frame.minX - bounds.minX) < 8 &&
            abs($0.frame.minY - bounds.minY) < 8 &&
            abs($0.frame.width - bounds.width) < 8 &&
            abs($0.frame.height - bounds.height) < 8
        }
        guard let target = candidates.first(where: { $0.title == title }) ?? (candidates.count == 1 ? candidates.first : nil) else {
            throw CaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: target)
        let config = SCStreamConfiguration()
        let scale = min(2, 2800 / max(bounds.width, bounds.height))
        config.width = max(1, Int(bounds.width * scale))
        config.height = max(1, Int(bounds.height * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.includeChildWindows = false
        config.scalesToFit = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(cgImage: image, size: bounds.size)
    }
}
