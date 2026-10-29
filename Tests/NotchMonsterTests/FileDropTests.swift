import AppKit
import Foundation
import Testing
@testable import NotchMonster

@MainActor
@Suite(.serialized)
struct FileDropTests {
    @Test func nearTopWindowCoordinatesAreAcceptedByFlippedDestination() throws {
        let fixture = try FileDropFixture()
        defer { fixture.close() }

        #expect(fixture.view.isFlipped)
        #expect(fixture.view.draggingEntered(fixture.sender) == .move)
        #expect(fixture.view.prepareForDragOperation(fixture.sender))
        #expect(!fixture.sender.animatesToDestination)
        #expect(abs(fixture.model.cursorOffset.height + 20) < 0.01)
    }

    @Test func releasingFarFromTheNotchIsRejected() throws {
        let fixture = try FileDropFixture()
        defer { fixture.close() }

        #expect(fixture.view.draggingEntered(fixture.sender) == .move)
        fixture.sender.draggingLocation = CGPoint(x: 230, y: 10)
        #expect(fixture.view.draggingUpdated(fixture.sender).isEmpty)
        #expect(!fixture.view.prepareForDragOperation(fixture.sender))
    }

    @Test func disabledMonsterRejectsNativeFileDrops() throws {
        let fixture = try FileDropFixture()
        defer { fixture.close() }
        fixture.model.enabled = false

        #expect(fixture.view.draggingEntered(fixture.sender).isEmpty)
        #expect(!fixture.view.prepareForDragOperation(fixture.sender))
    }

    @Test func retreatThenPauseWithinReachKeepsTheFileAndSkipsItsAction() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("notch-retreat-\(UUID().uuidString).txt")
        let contents = Data("Keep this fixture".utf8)
        try contents.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let fixture = try FileDropFixture(url: file)
        defer { fixture.close() }
        var animations = 0
        fixture.model.onFileConsumed = { _, _, _ in animations += 1 }

        #expect(fixture.view.draggingEntered(fixture.sender) == .move)
        // The notch is at y=210, so decreasing y moves away from it.
        fixture.sender.draggingLocation.y = 188
        // Two points of wobble keep the native drop accepted, even if paused.
        #expect(fixture.view.draggingUpdated(fixture.sender) == .move)
        for _ in 0..<4 { #expect(fixture.view.draggingUpdated(fixture.sender) == .move) }
        #expect(fixture.view.prepareForDragOperation(fixture.sender))
        fixture.sender.draggingLocation.y = 185
        #expect(fixture.view.draggingUpdated(fixture.sender).isEmpty)
        for _ in 0..<4 { #expect(fixture.view.draggingUpdated(fixture.sender).isEmpty) }
        fixture.model.reset() // The global watcher may see mouse-up first.
        #expect(!fixture.view.prepareForDragOperation(fixture.sender))
        #expect(!fixture.view.performDragOperation(fixture.sender))
        #expect(animations == 0)
        #expect(try Data(contentsOf: file) == contents)

        // Moving inward during the same native drag restores the operation.
        fixture.sender.draggingLocation.y = 190
        #expect(fixture.view.draggingUpdated(fixture.sender) == .move)
        #expect(fixture.view.prepareForDragOperation(fixture.sender))
    }

    @Test func armLengthPersistsAndRedrawsTheNativeCaptureSurface() async throws {
        let fixture = try FileDropFixture()
        defer { fixture.close() }
        fixture.model.onArmLengthChanged = { fixture.panel.refreshCaptureGeometry() }
        fixture.panel.setFileDropEnabled(true)
        let longerReach = fixture.panel.convertPoint(toScreen: CGPoint(x: 230, y: 30))
        fixture.panel.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        #expect(NSWindow.windowNumber(at: longerReach, belowWindowWithWindowNumber: 0) != fixture.panel.windowNumber)
        fixture.model.armLength = 240
        try await Task.sleep(for: .milliseconds(30))
        #expect(NSWindow.windowNumber(at: longerReach, belowWindowWithWindowNumber: 0) == fixture.panel.windowNumber)

        let suite = "notch-arm-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = MonsterModel(defaults: defaults)
        #expect(settings.armLength == 170)
        settings.armLength = 320
        #expect(MonsterModel(defaults: defaults).armLength == 320)
        #expect(settings.captureRadius == 320)
        settings.armLength = 900
        #expect(settings.armLength == 360)
        settings.armLength = 0
        #expect(settings.armLength == 80)
    }

    @Test func activePanelPreservesPerPixelRoutingAndIdlePanelIsOrderedOut() async throws {
        let fixture = try FileDropFixture(centered: true)
        defer { fixture.close() }

        #expect(!fixture.panel.isVisible)
        #expect(!fixture.panel.ignoresMouseEvents)
        let insideCapture = fixture.panel.convertPoint(toScreen: CGPoint(x: 230, y: 190))
        fixture.panel.trackFileDrag(at: insideCapture)
        fixture.panel.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(50))

        #expect(fixture.panel.isVisible)
        #expect(NSWindow.windowNumber(at: insideCapture, belowWindowWithWindowNumber: 0) == fixture.panel.windowNumber)
        let outsideCapture = fixture.panel.convertPoint(toScreen: CGPoint(x: 20, y: 20))
        fixture.panel.trackFileDrag(at: outsideCapture)
        #expect(fixture.panel.isVisible)
        #expect(NSWindow.windowNumber(at: outsideCapture, belowWindowWithWindowNumber: 0) != fixture.panel.windowNumber)

        fixture.panel.trackFileDrag(at: nil)
        #expect(!fixture.panel.isVisible)
        #expect(!fixture.panel.ignoresMouseEvents)

        // A second file drag must retain the shape after orderOut/orderFront.
        // Toggling ignoresMouseEvents instead makes the whole rectangle hit.
        fixture.panel.trackFileDrag(at: insideCapture)
        fixture.panel.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        #expect(fixture.panel.isVisible)
        #expect(!fixture.panel.ignoresMouseEvents)
        #expect(NSWindow.windowNumber(at: insideCapture, belowWindowWithWindowNumber: 0) == fixture.panel.windowNumber)
        #expect(NSWindow.windowNumber(at: outsideCapture, belowWindowWithWindowNumber: 0) != fixture.panel.windowNumber)
        fixture.panel.trackFileDrag(at: nil)
        #expect(!fixture.panel.isVisible)
        #expect(!fixture.panel.ignoresMouseEvents)
    }

    @Test func nativeOwnershipSurvivesMouseReleaseUntilDeferredDragEnd() async throws {
        let fixture = try FileDropFixture()
        defer { fixture.close() }

        fixture.panel.trackFileDrag(at: fixture.panel.convertPoint(toScreen: fixture.sender.draggingLocation))
        #expect(fixture.view.draggingEntered(fixture.sender) == .move)
        fixture.panel.trackFileDrag(at: nil)
        #expect(fixture.panel.isVisible)
        #expect(fixture.view.prepareForDragOperation(fixture.sender))

        fixture.view.draggingEnded(fixture.sender)
        #expect(fixture.panel.isVisible)
        try await Task.sleep(for: .milliseconds(30))
        #expect(!fixture.panel.isVisible)
    }

    @Test func leavingCaptureCirclePassesThroughWhileNativePanelRemainsAvailable() async throws {
        let fixture = try FileDropFixture()
        defer { fixture.close() }

        fixture.panel.trackFileDrag(at: fixture.panel.convertPoint(toScreen: fixture.sender.draggingLocation))
        #expect(fixture.view.draggingEntered(fixture.sender) == .move)
        #expect(fixture.panel.isVisible)
        let outsideCapture = fixture.panel.convertPoint(toScreen: CGPoint(x: 20, y: 20))
        fixture.panel.trackFileDrag(at: outsideCapture)
        fixture.panel.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        #expect(fixture.panel.isVisible)
        #expect(NSWindow.windowNumber(at: outsideCapture, belowWindowWithWindowNumber: 0) != fixture.panel.windowNumber)
        fixture.view.draggingExited(fixture.sender)
        #expect(fixture.panel.isVisible)
        fixture.panel.trackFileDrag(at: nil)
        #expect(!fixture.panel.isVisible)
    }

    @Test func modelUpdatesPreserveNativeRegistrationAndHitTarget() async throws {
        let fixture = try FileDropFixture()
        defer { fixture.close() }
        fixture.panel.setFileDropEnabled(true)
        // NSView.hitTest receives superview coordinates. Specify samples in
        // the flipped destination's local space, then convert for the API.
        let insidePoint = fixture.view.convert(CGPoint(x: 230, y: 20), to: fixture.view.superview)
        let outsidePoint = fixture.view.convert(CGPoint(x: 20, y: 20), to: fixture.view.superview)

        #expect(fixture.view.registeredDraggedTypes.contains(.fileURL))
        #expect(fixture.view.hitTest(insidePoint) === fixture.view)
        #expect(fixture.view.hitTest(outsidePoint) == nil)
        fixture.model.approach(
            cursor: CGPoint(x: fixture.screen.frame.midX, y: fixture.screen.frame.maxY - 40),
            center: CGPoint(x: fixture.screen.frame.midX, y: fixture.screen.frame.maxY),
            dragging: true
        )
        fixture.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        #expect(fixture.view.registeredDraggedTypes.contains(.fileURL))
        #expect(fixture.view.hitTest(insidePoint) === fixture.view)
        #expect(fixture.view.hitTest(outsidePoint) == nil)

        fixture.model.reset()
        fixture.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        #expect(fixture.view.registeredDraggedTypes.contains(.fileURL))
        #expect(fixture.view.hitTest(insidePoint) === fixture.view)
        #expect(fixture.view.hitTest(outsidePoint) == nil)
    }

    @Test func nativeDropTrashesOnlyTheFixtureAndInvokesAnimationOnce() async throws {
        let manager = FileManager.default
        let token = UUID().uuidString
        let directory = manager.temporaryDirectory.appendingPathComponent("notch-monster-drop-\(token)", isDirectory: true)
        let file = directory.appendingPathComponent("notch-monster-drop-\(token).txt")
        let originalContents = Data("Notch Monster native drop fixture \(token)".utf8)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: directory) }
        try originalContents.write(to: file)
        let trashDirectory = try manager.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: file, create: false)
        let trashedFixture = trashDirectory.appendingPathComponent(file.lastPathComponent)
        try #require(!manager.fileExists(atPath: trashedFixture.path))
        // Cleanup is restricted to this unique fixture, and only if its content
        // still matches what this test wrote. No existing user files are used.
        defer {
            if (try? Data(contentsOf: trashedFixture)) == originalContents {
                try? manager.removeItem(at: trashedFixture)
            }
        }

        let fixture = try FileDropFixture(url: file)
        defer { fixture.close() }
        var callbackCount = 0
        var callbackCursor: CGPoint?
        var callbackNotch: CGPoint?
        var retainedOwnershipInCallback = false
        fixture.model.onFileConsumed = { _, cursor, notch in
            callbackCount += 1
            callbackCursor = cursor
            callbackNotch = notch
            fixture.model.mood = .chewing
            fixture.panel.trackFileDrag(at: nil)
            retainedOwnershipInCallback = fixture.panel.isVisible
        }

        fixture.panel.trackFileDrag(at: fixture.panel.convertPoint(toScreen: fixture.sender.draggingLocation))
        #expect(fixture.view.draggingEntered(fixture.sender) == .move)
        // The global mouse monitor can see release before AppKit delivers the
        // native drop. Disabling the requested surface must not cancel it.
        fixture.panel.trackFileDrag(at: nil)
        #expect(fixture.panel.isVisible)
        try #require(fixture.view.prepareForDragOperation(fixture.sender))
        try #require(fixture.view.performDragOperation(fixture.sender))
        #expect(retainedOwnershipInCallback)
        #expect(fixture.panel.isVisible)
        #expect(!manager.fileExists(atPath: file.path))
        #expect(try Data(contentsOf: trashedFixture) == originalContents)
        #expect(callbackCount == 1)
        #expect(callbackCursor == fixture.panel.convertPoint(toScreen: fixture.sender.draggingLocation))
        #expect(callbackNotch == CGPoint(x: fixture.screen.frame.midX, y: fixture.screen.frame.maxY))

        // A duplicate callback for the same native drag must not trash a file
        // that has since appeared at the original path or run animation again.
        let replacementContents = Data("Replacement fixture \(token)".utf8)
        try replacementContents.write(to: file)
        #expect(fixture.view.performDragOperation(fixture.sender))
        #expect(try Data(contentsOf: file) == replacementContents)
        #expect(callbackCount == 1)
        fixture.view.concludeDragOperation(fixture.sender)
        #expect(fixture.panel.isVisible)
        try await Task.sleep(for: .milliseconds(30))
        #expect(!fixture.panel.isVisible)
        fixture.view.draggingEnded(fixture.sender)
        #expect(fixture.model.mood == .chewing)
    }

    @Test func raycastDropSendsEveryFileOnceAndLeavesOriginalsInPlace() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("notch-raycast-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = [directory.appendingPathComponent("first & #1.txt"), directory.appendingPathComponent("second café.txt")]
        for file in files { try Data(file.lastPathComponent.utf8).write(to: file) }

        let fixture = try FileDropFixture(url: files[0])
        defer { fixture.close() }
        fixture.model.fileAction = .raycast
        fixture.sender.draggingPasteboard.clearContents()
        fixture.sender.draggingPasteboard.writeObjects(files.map { $0 as NSURL })
        var requests: [[URL]] = []
        var animations = 0
        fixture.model.sendFilesToRaycast = { requests.append($0) }
        fixture.model.onFileConsumed = { _, _, _ in animations += 1 }

        #expect(fixture.view.draggingEntered(fixture.sender) == .copy)
        #expect(fixture.view.performDragOperation(fixture.sender))
        #expect(fixture.view.performDragOperation(fixture.sender))
        #expect(requests == [files])
        #expect(animations == 1)
        for file in files { #expect(try Data(contentsOf: file) == Data(file.lastPathComponent.utf8)) }
    }

    @Test func failedRaycastHandoffDoesNotFallBackToTrashOrAnimate() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("notch-raycast-\(UUID().uuidString).txt")
        let contents = Data("Keep this fixture".utf8)
        try contents.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let fixture = try FileDropFixture(url: file)
        defer { fixture.close() }
        fixture.model.fileAction = .raycast
        var attempts = 0
        var animations = 0
        fixture.model.sendFilesToRaycast = { _ in
            attempts += 1
            throw RaycastHandoff.Failure.couldNotOpen
        }
        fixture.model.onFileConsumed = { _, _, _ in animations += 1 }

        #expect(!fixture.view.performDragOperation(fixture.sender))
        #expect(!fixture.view.performDragOperation(fixture.sender))
        #expect(attempts == 1)
        #expect(animations == 0)
        #expect(fixture.model.message.contains("Your files were kept"))
        #expect(try Data(contentsOf: file) == contents)
    }
}

@MainActor
private struct FileDropFixture {
    let model: MonsterModel
    let panel: MonsterPanel
    let screen: NSScreen
    let view: DropCaptureView
    let sender: MockDraggingInfo
    private let defaultsName: String

    init(url: URL? = nil, centered: Bool = false) throws {
        _ = NSApplication.shared
        screen = try #require(NSScreen.screens.first)
        defaultsName = "notch-monster-tests.\(UUID().uuidString)"
        model = MonsterModel(defaults: UserDefaults(suiteName: defaultsName)!)
        let frame = CGRect(x: screen.frame.midX - 230, y: centered ? screen.frame.midY - 105 : screen.frame.maxY - 210, width: 460, height: 210)
        panel = MonsterPanel(frame: frame, model: model)
        panel.isReleasedWhenClosed = false
        view = try #require(panel.contentView as? DropCaptureView)
        sender = MockDraggingInfo(window: panel, url: url ?? URL(fileURLWithPath: "/tmp/notch-monster-\(UUID().uuidString).txt"))
        // The panel starts ordered out and its native lifecycle controls when
        // it becomes visible. No window is made key or activated by these tests.
    }

    func close() {
        sender.draggingPasteboard.releaseGlobally()
        panel.close()
        UserDefaults.standard.removePersistentDomain(forName: defaultsName)
    }
}

@MainActor
private final class MockDraggingInfo: NSObject, NSDraggingInfo {
    let draggingDestinationWindow: NSWindow?
    let draggingSourceOperationMask: NSDragOperation = .every
    var draggingLocation = CGPoint(x: 230, y: 190)
    var draggedImageLocation: CGPoint { draggingLocation }
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any? { nil }
    let draggingSequenceNumber = 42
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = true
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    init(window: NSWindow, url: URL) {
        draggingDestinationWindow = window
        super.init()
        draggingPasteboard.writeObjects([url as NSURL])
    }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
