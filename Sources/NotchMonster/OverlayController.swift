import AppKit
import OSLog
import SwiftUI

@MainActor
final class OverlayController {
    private let model: MonsterModel
    private var panels: [MonsterPanel] = []
    private var artworkPanels: [NSPanel] = []
    private var observers: [NSObjectProtocol] = []

    init(model: MonsterModel) { self.model = model }

    var hasActiveFileDrag: Bool { panels.contains { $0.hasActiveFileDrag } }

    func trackFileDrag(at point: CGPoint?) {
        panels.forEach { $0.trackFileDrag(at: point) }
    }

    func install() {
        rebuild()
        model.onArmLengthChanged = { [weak self] in
            self?.panels.forEach { $0.refreshCaptureGeometry() }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        })
    }

    private func rebuild() {
        panels.forEach { $0.close() }
        artworkPanels.forEach { $0.close() }
        artworkPanels.removeAll()
        panels = NSScreen.screens.map { screen in
            // Room for the longest arm plus the hand and fur on either side.
            let width = (MonsterModel.armLengthRange.upperBound + 64) * 2
            let height = MonsterModel.armLengthRange.upperBound + 64
            let frame = NSRect(
                x: screen.frame.midX - width / 2,
                y: screen.frame.maxY - height,
                width: width,
                height: height
            )
            let panel = MonsterPanel(frame: frame, model: model)
            // Artwork is always click-through, including the fur and shadows
            // outside the exact capture radius. Only the native surface below
            // it can own a file drop.
            let artwork = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            artwork.isReleasedWhenClosed = false
            artwork.isOpaque = false
            artwork.backgroundColor = .clear
            artwork.hasShadow = false
            artwork.level = .screenSaver
            artwork.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            artwork.hidesOnDeactivate = false
            artwork.ignoresMouseEvents = true
            artwork.contentView = NSHostingView(rootView: MonsterView(model: model, screenFrame: screen.frame))
            artwork.orderFrontRegardless()
            artworkPanels.append(artwork)
            return panel
        }
    }
}

@MainActor
final class MonsterPanel: NSPanel {
    private var fileDropRequested = false
    private var nativeDragSequence: Int?
    var hasActiveFileDrag: Bool { fileDropRequested || nativeDragSequence != nil }

    init(frame: NSRect, model: MonsterModel) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Keep the native destination below the system's dragging image.
        // The separate click-through artwork can remain at screen-saver level.
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovable = false
        // Leave ignoresMouseEvents at its default. Toggling it true -> false
        // makes WindowServer treat this shaped window as a solid rectangle.
        // Idle receivers are ordered out instead; artwork is a separate panel.
        isReleasedWhenClosed = false
        let dropView = DropCaptureView(model: model, frame: NSRect(origin: .zero, size: frame.size))
        contentView = dropView
        dropView.onDragEntered = { [weak self] sequence in
            self?.nativeDragSequence = sequence
            self?.updateDropSurface()
        }
        dropView.onDragExited = { [weak self] sequence in
            guard self?.nativeDragSequence == sequence else { return }
            self?.nativeDragSequence = nil
            self?.updateDropSurface()
        }
        dropView.onDragEnded = { [weak self] sequence in
            // Keep the destination in the window server until AppKit returns
            // from its final drop callback. Mouse-up is not drag completion.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.nativeDragSequence == sequence else { return }
                self.nativeDragSequence = nil
                self.fileDropRequested = false
                self.updateDropSurface()
            }
        }
    }

    func setFileDropEnabled(_ enabled: Bool) {
        fileDropRequested = enabled
        updateDropSurface()
    }

    func refreshCaptureGeometry() {
        contentView?.needsDisplay = true
        if isVisible { displayIfNeeded() }
    }

    func trackFileDrag(at point: CGPoint?) {
        // Prepare the shaped destination before the pointer enters its reach.
        // Nil means physical mouse-up, which may precede the native callback.
        setFileDropEnabled(point != nil)
    }

    private func updateDropSurface() {
        let enabled = fileDropRequested || nativeDragSequence != nil
        guard isVisible != enabled else { return }
        (contentView as? DropCaptureView)?.isCaptureSurfaceEnabled = enabled
        if enabled {
            orderFrontRegardless()
            displayIfNeeded()
        } else {
            orderOut(nil)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DropCaptureView: NSView {
    private let logger = Logger(subsystem: "com.notchmonster.app", category: "FileCapture")
    private let model: MonsterModel
    private var handledSequence: Int?
    private var handledSuccessfully = false
    private var trackedSequence: Int?
    private var attachment = DragAttachmentPolicy()
    private let readingOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    var onDragEntered: ((Int) -> Void)?
    var onDragExited: ((Int) -> Void)?
    var onDragEnded: ((Int) -> Void)?
    var isCaptureSurfaceEnabled = false {
        didSet { needsDisplay = true }
    }

    init(model: MonsterModel, frame: NSRect) {
        self.model = model
        super.init(frame: frame)
        wantsLayer = true
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("NSFilenamesPboardType")])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        guard isCaptureSurfaceEnabled else { return }
        // Keep an almost invisible native surface independent of the artwork.
        // Outside the circle, fully transparent pixels pass drags through.
        let radius = model.captureRadius * 0.95
        NSColor.black.withAlphaComponent(1.0 / 255.0).setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.midX - radius, y: -radius, width: radius * 2, height: radius * 2)).fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard !isHidden, bounds.contains(localPoint),
              DragSessionPolicy.canCapture(cursor: localPoint, notch: CGPoint(x: bounds.midX, y: 0), radius: model.captureRadius) else { return nil }
        return self
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepted = accepts(sender)
        if accepted {
            onDragEntered?(sender.draggingSequenceNumber)
            updateDrag(sender)
        }
        logger.notice("FILE_ENTER sequence=\(sender.draggingSequenceNumber) accepted=\(accepted)")
        return accepted ? (model.fileAction == .raycast ? .copy : .move) : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepted = accepts(sender)
        if accepted {
            onDragEntered?(sender.draggingSequenceNumber)
            updateDrag(sender)
        } else {
            resetUnconsumedDrag(sender)
            onDragExited?(sender.draggingSequenceNumber)
        }
        return accepted ? (model.fileAction == .raycast ? .copy : .move) : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        resetUnconsumedDrag(sender)
        attachment.reset()
        if let sender { onDragExited?(sender.draggingSequenceNumber) }
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        resetUnconsumedDrag(sender)
        attachment.reset()
        trackedSequence = nil
        onDragEnded?(sender.draggingSequenceNumber)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        guard let sender else { return }
        logger.notice("FILE_CONCLUDE sequence=\(sender.draggingSequenceNumber)")
        attachment.reset()
        trackedSequence = nil
        onDragEnded?(sender.draggingSequenceNumber)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let accepted = accepts(sender)
        if accepted { sender.animatesToDestination = false }
        if !accepted { logger.notice("FILE_REJECT sequence=\(sender.draggingSequenceNumber) stage=prepare") }
        return accepted
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let sequence = sender.draggingSequenceNumber
        if handledSequence == sequence {
            logger.notice("FILE_DROP duplicate ignored sequence=\(sequence)")
            return handledSuccessfully
        }
        guard accepts(sender), let location = dropLocation(sender) else {
            logger.notice("FILE_REJECT sequence=\(sequence) stage=drop")
            resetUnconsumedDrag(sender)
            return false
        }
        guard let payload = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: readingOptions) as? [URL], !payload.isEmpty else {
            logger.notice("FILE_REJECT sequence=\(sequence) reason=no-local-files")
            model.fail("This drop does not contain local files.")
            return false
        }
        var seen = Set<URL>()
        let urls = payload.filter { $0.isFileURL && seen.insert($0.standardizedFileURL).inserted }
        guard let firstURL = urls.first else { return false }

        // Capture the icon while its original path still exists. Native drag
        // images disappear as soon as AppKit finishes the drop transaction.
        let icon = NSWorkspace.shared.icon(forFile: firstURL.path).copy() as! NSImage
        icon.size = NSSize(width: 64, height: 64)
        handledSequence = sequence
        handledSuccessfully = false
        logger.notice("FILE_DROP sequence=\(sequence) count=\(urls.count)")
        if model.fileAction == .raycast {
            do {
                try model.sendFilesToRaycast(urls)
                handledSuccessfully = true
                logger.notice("FILE_RAYCAST handedOff=\(urls.count)")
                model.onFileConsumed?(icon, location.cursor, location.notch)
                return true
            } catch {
                logger.error("FILE_RAYCAST failed; files unchanged")
                model.fail(error.localizedDescription)
                return false
            }
        }
        var trashedCount = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashedCount += 1
            } catch {
                let failure = error as NSError
                logger.error("FILE_TRASH failed domain=\(failure.domain, privacy: .public) code=\(failure.code)")
            }
        }
        let failedCount = urls.count - trashedCount
        logger.notice("FILE_TRASH result moved=\(trashedCount) failed=\(failedCount)")
        guard failedCount == 0 else {
            if trashedCount == 0 {
                model.fail("Could not move \(failedCount == 1 ? "the file" : "the \(failedCount) files") to Trash.")
            } else {
                model.fail("Moved \(trashedCount) to Trash; \(failedCount) could not be moved.")
            }
            return false
        }
        handledSuccessfully = true
        model.onFileConsumed?(icon, location.cursor, location.notch)
        return true
    }

    private func updateDrag(_ sender: NSDraggingInfo) {
        guard handledSequence != sender.draggingSequenceNumber,
              let location = dropLocation(sender) else { return }
        model.approach(cursor: location.cursor, center: location.notch, dragging: true)
    }

    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        guard model.enabled, let location = dropLocation(sender),
              sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: readingOptions) else { return false }
        if trackedSequence != sender.draggingSequenceNumber {
            attachment.reset()
            trackedSequence = sender.draggingSequenceNumber
        }
        return attachment.update(
            cursor: location.cursor,
            notch: location.notch,
            radius: model.captureRadius
        )
    }

    private func dropLocation(_ sender: NSDraggingInfo) -> (cursor: CGPoint, notch: CGPoint)? {
        guard let window, let screen = window.screen else { return nil }
        // NSDraggingInfo uses window coordinates, whereas our artwork is
        // flipped. Convert directly to global AppKit coordinates so both the
        // file target and the window watcher use the same notch and cursor.
        return (
            window.convertPoint(toScreen: sender.draggingLocation),
            CGPoint(x: screen.frame.midX, y: screen.frame.maxY)
        )
    }

    private func resetUnconsumedDrag(_ sender: NSDraggingInfo?) {
        if let sender, handledSequence == sender.draggingSequenceNumber { return }
        guard model.mood != .chewing, model.mood != .pleased, model.mood != .error else { return }
        model.reset()
    }
}
