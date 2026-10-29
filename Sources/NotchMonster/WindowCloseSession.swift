import AppKit
import ApplicationServices

/// Keeps the original application identity across the asynchronous yank, and
/// only requests a normal quit after its window was confirmed closed.
@MainActor
final class WindowCloseSession {
    enum QuitResult: String {
        case requested, declined, alreadyTerminated, windowsRemain, unavailable, closeNotConfirmed
    }

    private let window: AXUIElement
    private let isTerminated: () -> Bool
    private let readWindows: () -> [AXUIElement]?
    private let requestQuit: () -> Bool
    private var closeConfirmed = false
    private var quitResult: QuitResult?

    convenience init?(window: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              pid != ProcessInfo.processInfo.processIdentifier,
              let owner = NSRunningApplication(processIdentifier: pid) else { return nil }
        let application = AXUIElementCreateApplication(pid)
        self.init(window: window, isTerminated: { owner.isTerminated }, readWindows: {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success else {
                return nil
            }
            // Do not filter by visibility, minimization, Space, or close button.
            // A remaining document, panel, or dialog keeps the app running.
            return value as? [AXUIElement]
        }, requestQuit: { owner.terminate() })
    }

    init(window: AXUIElement, isTerminated: @escaping () -> Bool,
         readWindows: @escaping () -> [AXUIElement]?, requestQuit: @escaping () -> Bool) {
        self.window = window
        self.isTerminated = isTerminated
        self.readWindows = readWindows
        self.requestQuit = requestQuit
    }

    func isClosed() -> Bool {
        if isTerminated() {
            closeConfirmed = true
            return true
        }
        guard let windows = readWindows() else { return false }
        let closed = !windows.contains { CFEqual($0, window) }
        if closed { closeConfirmed = true }
        return closed
    }

    /// Called once the animation finishes. Re-read now because a window or
    /// confirmation dialog may have opened since close verification.
    @discardableResult
    func quitIfLastWindow() -> QuitResult {
        if let quitResult { return quitResult }
        let result: QuitResult
        if !closeConfirmed {
            result = .closeNotConfirmed
        } else if isTerminated() {
            result = .alreadyTerminated
        } else if let windows = readWindows() {
            result = windows.isEmpty ? (requestQuit() ? .requested : .declined) : .windowsRemain
        } else {
            result = .unavailable
        }
        quitResult = result
        return result
    }
}
