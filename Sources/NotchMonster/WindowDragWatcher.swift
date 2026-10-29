import AppKit
import ApplicationServices
import OSLog

@MainActor
final class WindowDragWatcher {
    private let logger = Logger(subsystem: "com.notchmonster.app", category: "WindowCapture")
    private let model: MonsterModel
    private let animator: ConsumptionAnimator
    private let updateFileDropTarget: (CGPoint?) -> Void
    private var monitors: [Any] = []
    private var poller: Timer?
    private var session: DragSessionPolicy?
    private var candidateWindow: AXUIElement?
    private var startPosition: CGPoint?
    private var movedWindow = false
    private var fileDrag = false
    private var sawDragEvent = false
    private var consuming = false
    private var lastPoint = CGPoint.zero
    private var wasInZone = false
    private var attachment = DragAttachmentPolicy()
    var isBusy: Bool { session != nil || consuming }

    init(model: MonsterModel, animator: ConsumptionAnimator, updateFileDropTarget: @escaping (CGPoint?) -> Void) {
        self.model = model
        self.animator = animator
        self.updateFileDropTarget = updateFileDropTarget
    }

    func start() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        // AppKit documents that both monitors run on the main thread. Process
        // them in order; an extra Task can run after the pointer has moved.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) { monitors.append(monitor) }
        logger.notice("READY trusted=\(AXIsProcessTrusted())")
        for screen in NSScreen.screens {
            logger.notice("DISPLAY frame=\(String(describing: screen.frame), privacy: .public)")
        }
    }

    func stop() {
        clear()
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    func consumeFile(icon: NSImage, cursor: CGPoint, notch: CGPoint) {
        clear()
        consuming = true
        let completionMessage = model.fileAction == .raycast ? "Sent to Raycast. Choose an action there." : "Moved to Trash"
        Task { @MainActor in
            let frame = CGRect(x: cursor.x - 24, y: cursor.y - 24, width: 48, height: 48)
            _ = await animator.yank(image: icon, frame: frame, grabPoint: cursor, notch: notch, crumple: false, model: model)
            model.reset()
            model.message = completionMessage
            consuming = false
        }
    }

    private func handle(_ event: NSEvent) {
        guard model.enabled, !consuming else { return }
        let point: CGPoint
        if let location = event.cgEvent?.location {
            point = CGPoint(x: location.x, y: primaryTop - location.y)
        } else {
            point = NSEvent.mouseLocation
        }
        switch event.type {
        case .leftMouseDown:
            clear()
            model.reset()
            session = DragSessionPolicy(pasteboardChangeCount: NSPasteboard(name: .drag).changeCount)
            lastPoint = point
            if let screen = screen(at: point) {
                attachment.update(cursor: point, notch: CGPoint(x: screen.frame.midX, y: screen.frame.maxY), radius: model.captureRadius)
            }
            candidateWindow = window(at: point)
            startPosition = candidateWindow.flatMap { position(of: $0) }
            var pid: pid_t = 0
            if let candidateWindow { AXUIElementGetPid(candidateWindow, &pid) }
            logger.notice("DOWN pid=\(pid) board=\(self.session!.pasteboardChangeCount)")
            logger.notice("DOWN point=\(String(describing: point), privacy: .public) windowOrigin=\(String(describing: self.startPosition), privacy: .public)")
            startPolling()
        case .leftMouseDragged:
            guard session != nil else { return }
            sawDragEvent = true
            update(at: point)
        case .leftMouseUp:
            guard session != nil else { return }
            update(at: point)
            finish(at: point)
        default: break
        }
    }

    private var primaryTop: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    private func startPolling() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.session != nil else { return }
                let point = NSEvent.mouseLocation
                if CGEventSource.buttonState(.combinedSessionState, button: .left) {
                    self.update(at: point)
                } else {
                    self.finish(at: point)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        poller = timer
    }

    private func update(at point: CGPoint) {
        guard let session else { return }
        lastPoint = point
        let board = NSPasteboard(name: .drag)
        let freshPayload = session.hasFreshPasteboard(board.changeCount)

        // A file URL left by a previous drag MUST NOT divert a window drag.
        // Actual file deletion happens only in NSDraggingDestination on a drop.
        if freshPayload && !fileDrag {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            if let urls = board.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
                fileDrag = true
                logger.notice("CLASSIFY file freshBoard=\(board.changeCount)")
            }
        }
        if !fileDrag, model.closeWindows, let window = candidateWindow, let startPosition,
           let current = position(of: window), DragSessionPolicy.windowMoved(from: startPosition, to: current) {
            if !movedWindow { logger.notice("CLASSIFY moved window; staleBoardIgnored=\(!freshPayload)") }
            movedWindow = true
        }
        guard fileDrag || movedWindow else { return }
        guard let screen = screen(at: point) else { model.reset(); return }
        let notch = CGPoint(x: screen.frame.midX, y: screen.frame.maxY)
        // File feedback starts only once AppKit actually acquires the native
        // drop destination. An observed pasteboard is not an accepted drop.
        if !fileDrag {
            if attachment.update(cursor: point, notch: notch, radius: model.captureRadius) {
                model.approach(cursor: point, center: notch, dragging: true)
            } else {
                model.reset()
            }
        }
        let inZone = DragSessionPolicy.canCapture(cursor: point, notch: notch, radius: model.captureRadius)
        if inZone != wasInZone {
            logger.notice("ZONE inside=\(inZone) file=\(self.fileDrag) window=\(self.movedWindow)")
            wasInZone = inZone
        }
        // Only a live file drag gets a native drop surface. Window drags remain
        // click-through from mouse-down through mouse-up.
        updateFileDropTarget(fileDrag ? point : nil)
        if fileDrag && !inZone { model.reset() }
    }

    private func finish(at point: CGPoint) {
        guard session != nil else { return }
        poller?.invalidate()
        poller = nil
        if fileDrag {
            // The panel retains its native drag ownership through AppKit's
            // conclude/ended callback, even after this mouse session ends.
            clear()
            if model.mood != .chewing && model.mood != .pleased && model.mood != .error { model.reset() }
            return
        }
        guard model.closeWindows, movedWindow, let window = candidateWindow,
              let screen = screen(at: point) else {
            if sawDragEvent { logger.notice("RELEASE cancelled: no moved window") }
            clear()
            model.reset()
            return
        }
        let notch = CGPoint(x: screen.frame.midX, y: screen.frame.maxY)
        guard attachment.update(cursor: point, notch: notch, radius: model.captureRadius) else {
            logger.notice("RELEASE cancelled: hand detached or outside reach")
            clear()
            model.reset()
            return
        }
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        logger.notice("RELEASE window pid=\(pid)")
        clear()
        consuming = true
        Task { @MainActor in
            await pullIntoNotchAndClose(window, notch: notch, grabPoint: point)
            consuming = false
        }
    }

    private func clear() {
        poller?.invalidate()
        poller = nil
        session = nil
        candidateWindow = nil
        startPosition = nil
        movedWindow = false
        fileDrag = false
        sawDragEvent = false
        wasInZone = false
        attachment.reset()
        updateFileDropTarget(nil)
    }

    private func screen(at point: CGPoint) -> NSScreen? {
        // Include the top edge itself, which CGRect.contains normally excludes.
        NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }
    }

    private func window(at point: CGPoint) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        var hit: AXUIElement?
        AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(primaryTop - point.y), &hit)
        var node = hit
        for _ in 0..<16 {
            guard let element = node else { break }
            if attribute(element, kAXRoleAttribute) as? String == kAXWindowRole, usable(element) { return element }
            if let window = elementAttribute(element, kAXWindowAttribute), usable(window) { return window }
            node = elementAttribute(element, kAXParentAttribute)
        }
        // A focused-window fallback is accepted only when the pointer is in
        // that window. Movement is still required before it can be consumed.
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let window = elementAttribute(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute),
              usable(window), let origin = position(of: window), let size = size(of: window),
              CGRect(origin: origin, size: size).contains(CGPoint(x: point.x, y: primaryTop - point.y)) else { return nil }
        return window
    }

    private func usable(_ window: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              pid != ProcessInfo.processInfo.processIdentifier else { return false }
        return elementAttribute(window, kAXCloseButtonAttribute) != nil
    }

    private func pullIntoNotchAndClose(_ window: AXUIElement, notch: CGPoint, grabPoint: CGPoint) async {
        try? await Task.sleep(for: .milliseconds(45))
        guard AXIsProcessTrusted(), let origin = position(of: window), let originalSize = size(of: window),
              let closeButton = elementAttribute(window, kAXCloseButtonAttribute),
              let closeSession = WindowCloseSession(window: window) else {
            logger.error("CAPTURE failed to read geometry/close button trusted=\(AXIsProcessTrusted())")
            model.fail("Window access failed. Check Accessibility in Settings.")
            return
        }
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        do {
            let snapshot = try await WindowSnapshot.capture(pid: pid, bounds: CGRect(origin: origin, size: originalSize), title: attribute(window, kAXTitleAttribute) as? String)
            logger.notice("SNAPSHOT captured pid=\(pid)")
            let frame = CGRect(x: origin.x, y: primaryTop - origin.y - originalSize.height, width: originalSize.width, height: originalSize.height)
            let ownerPID = pid
            let completed = await animator.yank(
                image: snapshot, frame: frame, grabPoint: grabPoint,
                notch: notch, crumple: true, model: model
            ) {
                let result = AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
                self.logger.notice("CLOSE pid=\(ownerPID) result=\(result.rawValue)")
                guard result == .success else { return false }
                for _ in 0..<16 {
                    if closeSession.isClosed() {
                        self.logger.notice("VERIFIED window removed pid=\(ownerPID)")
                        return true
                    }
                    try? await Task.sleep(for: .milliseconds(25))
                }
                return false
            }
            if completed {
                logger.notice("YANK completed window pid=\(pid)")
                model.consume("window")
                let quitResult = closeSession.quitIfLastWindow()
                logger.notice("LAST_WINDOW_QUIT pid=\(pid) result=\(quitResult.rawValue, privacy: .public)")
            } else {
                logger.error("CLOSE not confirmed pid=\(pid)")
                model.fail("Window is still open; it may need confirmation.")
            }
        } catch {
            logger.error("SNAPSHOT failed: \(error.localizedDescription, privacy: .public)")
            model.fail(error.localizedDescription)
        }
    }

    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    private func elementAttribute(_ element: AXUIElement, _ key: String) -> AXUIElement? {
        guard let value = attribute(element, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func position(of element: AXUIElement) -> CGPoint? {
        guard let value = attribute(element, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private func size(of element: AXUIElement) -> CGSize? {
        guard let value = attribute(element, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

}
