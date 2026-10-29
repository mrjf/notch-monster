import Foundation
import Testing
@testable import NotchMonster

struct DragSessionPolicyTests {
    @Test func oldPasteboardPayloadDoesNotTurnAWindowDragIntoAFileDrag() {
        let session = DragSessionPolicy(pasteboardChangeCount: 17)

        // A prior file drag can leave URLs behind. Merely seeing those URLs
        // again must not make them eligible for deletion in a new gesture.
        #expect(!session.hasFreshPasteboard(17))
        #expect(!session.hasFreshPasteboard(17))
    }

    @Test func aNewPasteboardGenerationBelongsToTheCurrentGesture() {
        let session = DragSessionPolicy(pasteboardChangeCount: 17)

        #expect(session.hasFreshPasteboard(18))
        #expect(session.hasFreshPasteboard(19))
    }

    @Test func eachGestureStartsWithANewPasteboardBaseline() {
        let fileDrag = DragSessionPolicy(pasteboardChangeCount: 17)
        #expect(fileDrag.hasFreshPasteboard(18))

        let subsequentWindowDrag = DragSessionPolicy(pasteboardChangeCount: 18)
        #expect(!subsequentWindowDrag.hasFreshPasteboard(18))
    }

    @Test func textSelectionAndPointerMotionAreNotWindowMotion() {
        let origin = CGPoint(x: 100, y: 140)

        #expect(!DragSessionPolicy.windowMoved(from: origin, to: origin))
        #expect(!DragSessionPolicy.windowMoved(from: origin, to: CGPoint(x: 102, y: 140)))
        #expect(DragSessionPolicy.windowMoved(from: origin, to: CGPoint(x: 105, y: 140)))
        #expect(DragSessionPolicy.windowMoved(from: origin, to: CGPoint(x: 100, y: 136)))
    }

    @Test func movingAwayAfterApproachingCancelsCapture() {
        let notch = CGPoint(x: 720, y: 900)
        let nearNotch = CGPoint(x: 720, y: 850)
        let releaseFarAway = CGPoint(x: 720, y: 600)

        #expect(DragSessionPolicy.canCapture(cursor: nearNotch, notch: notch, radius: 170))
        #expect(!DragSessionPolicy.canCapture(cursor: releaseFarAway, notch: notch, radius: 170))
    }

    @Test func captureWorksOnDisplaysWithNegativeOrigins() {
        let notch = CGPoint(x: -960, y: -200)

        #expect(DragSessionPolicy.canCapture(cursor: CGPoint(x: -1020, y: -260), notch: notch, radius: 170))
        #expect(!DragSessionPolicy.canCapture(cursor: CGPoint(x: -960, y: -400), notch: notch, radius: 170))
        #expect(DragSessionPolicy.windowMoved(from: CGPoint(x: -1500, y: -400), to: CGPoint(x: -1490, y: -390)))
    }

    @Test func movingAwayReleasesInsideTheZoneAndPausingDoesNotReattach() {
        var hand = DragAttachmentPolicy()
        let notch = CGPoint(x: 720, y: 900)
        func update(_ distance: CGFloat) -> Bool {
            hand.update(cursor: CGPoint(x: 720, y: 900 - distance), notch: notch, radius: 170)
        }
        #expect(update(120))
        #expect(update(80))
        for _ in 0..<100 { #expect(update(80)) }
        #expect(update(84.75))
        // Pausing inside the movement buffer must not expire a timer.
        for _ in 0..<100 { #expect(update(84.75)) }
        #expect(!update(85))
        // This is also the final mouse-up sample: still inside the radius,
        // but the window must be placed instead of being closed.
        for _ in 0..<100 { #expect(!update(85)) }
        #expect(!update(100))
        #expect(update(99))
    }

    @Test func slowRetreatAccumulatesAndJitterDoesNotChangeAttachment() {
        var hand = DragAttachmentPolicy()
        let notch = CGPoint.zero
        func update(_ distance: CGFloat) -> Bool {
            hand.update(cursor: CGPoint(x: 0, y: -distance), notch: notch, radius: 170)
        }
        #expect(update(80))
        #expect(update(79.75))
        for distance in stride(from: CGFloat(80), through: 84.5, by: 0.25) {
            #expect(update(distance))
        }
        #expect(!update(84.75))
        #expect(!update(85))
        #expect(!update(84.75))
        #expect(!update(84.5))
        #expect(!update(84.25))
        #expect(update(84))
    }

    @Test func reentryNewGesturesAndDisplayChangesStartFresh() {
        var hand = DragAttachmentPolicy()
        func update(_ cursor: CGPoint, notch: CGPoint = .zero) -> Bool {
            hand.update(cursor: cursor, notch: notch, radius: 170)
        }
        #expect(update(CGPoint(x: 0, y: -80)))
        #expect(!update(CGPoint(x: 0, y: -90)))
        #expect(!update(CGPoint(x: 0, y: -200)))
        #expect(update(CGPoint(x: 0, y: -120)))
        hand.reset()
        #expect(update(CGPoint(x: 0, y: -125)))
        #expect(update(CGPoint(x: -960, y: -280), notch: CGPoint(x: -960, y: -200)))
    }
}
