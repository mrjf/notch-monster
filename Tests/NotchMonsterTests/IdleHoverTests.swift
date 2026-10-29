import AppKit
import Testing
@testable import NotchMonster

@MainActor
struct IdleHoverTests {
    @Test func battingIsOffByDefaultAndOnlyAnExplicitPreferenceEnablesIt() throws {
        let fixture = try HoverFixture()
        defer { fixture.close() }
        #expect(!fixture.model.batCursorAway)
        #expect(fixture.defaults.object(forKey: "batCursorAway") == nil)
        fixture.model.batCursorAway = true
        #expect(MonsterModel(defaults: fixture.defaults).batCursorAway)
        fixture.model.batCursorAway = false
        #expect(!MonsterModel(defaults: fixture.defaults).batCursorAway)
    }

    @Test func greetingRequiresEmptyHandsBelowTheMenuAndNearTheCenter() throws {
        let fixture = try HoverFixture()
        defer { fixture.close() }
        for point in [CGPoint(x: 600, y: 790), CGPoint(x: 450, y: 740), CGPoint(x: 600, y: 500)] {
            fixture.move(to: point)
            #expect(fixture.model.idleArm == nil)
        }
        fixture.buttons = true
        fixture.move(to: CGPoint(x: 600, y: 744))
        #expect(fixture.model.idleArm == nil)
        fixture.buttons = false
        fixture.busy = true
        fixture.move(to: CGPoint(x: 600, y: 744))
        #expect(fixture.model.idleArm == nil)
        fixture.busy = false
        fixture.move(to: CGPoint(x: 600, y: 744))
        fixture.advance(0.2)
        #expect(fixture.model.idleArm?.extensionAmount == 1)
        #expect(fixture.model.idleArm?.screenFrame == fixture.screen.frame)
        #expect(fixture.warps.isEmpty)
    }

    @Test func stayingUnderTheNotchWavesOnceAndRequiresExitAndCooldown() {
        var policy = IdleHoverPolicy()
        let zone = CGRect(x: 532, y: 690, width: 136, height: 83)
        let inside = CGPoint(x: 600, y: 744), outside = CGPoint(x: 900, y: 500)
        let first = policy.enter(point: inside, zone: zone, eligible: true, now: 0)
        #expect(first)
        let remaining = policy.enter(point: inside, zone: zone, eligible: true, now: 0.8)
        #expect(!remaining)
        let smallWobble = policy.enter(point: CGPoint(x: 675, y: 744), zone: zone, eligible: true, now: 1)
        #expect(!smallWobble)
        let returnedFromWobble = policy.enter(point: inside, zone: zone, eligible: true, now: 1.1)
        #expect(!returnedFromWobble)
        let exited = policy.enter(point: outside, zone: zone, eligible: true, now: 1.2)
        #expect(!exited)
        let tooSoon = policy.enter(point: inside, zone: zone, eligible: true, now: 1.3)
        #expect(!tooSoon)
        let second = policy.enter(point: inside, zone: zone, eligible: true, now: 1.6)
        #expect(second)
        let stillThere = policy.enter(point: inside, zone: zone, eligible: true, now: 10)
        #expect(!stillThere)
    }

    @Test func waveRetractsWithoutMovingTheCursorAndDoesNotTakeOverADrag() throws {
        let fixture = try HoverFixture()
        defer { fixture.close() }
        fixture.move(to: fixture.point)
        fixture.advance(0.2)
        #expect(fixture.model.idleArm != nil)
        fixture.model.approach(cursor: fixture.point, center: CGPoint(x: 600, y: 800), dragging: true)
        fixture.advance(0.2)
        #expect(fixture.model.idleArm == nil)
        #expect(fixture.model.mood == .reaching)
        #expect(fixture.model.cursorOffset == CGSize(width: 0, height: -56))
        #expect(fixture.warps.isEmpty)
    }

    @Test func swatWaitsForContactThenMovesCursorAndRealMovementCancels() throws {
        let fixture = try HoverFixture()
        defer { fixture.close() }
        fixture.model.batCursorAway = true
        fixture.move(to: fixture.point)
        fixture.advance(0.12)
        #expect(fixture.warps.isEmpty)
        fixture.advance(0.07)
        fixture.advance(0.05)
        #expect(fixture.point.y < 744)
        #expect(fixture.point.x > 600)
        let count = fixture.warps.count
        fixture.move(to: CGPoint(x: fixture.point.x + 1, y: fixture.point.y))
        #expect(fixture.model.idleArm == nil)
        fixture.advance(0.1)
        #expect(fixture.warps.count == count)
    }

    @Test func movingIntoTheMenuBarBeforeContactCancelsTheSwat() throws {
        let fixture = try HoverFixture()
        defer { fixture.close() }
        fixture.model.batCursorAway = true
        fixture.move(to: fixture.point)
        fixture.advance(0.12)
        fixture.move(to: CGPoint(x: 600, y: 785))
        #expect(fixture.model.idleArm == nil)
        fixture.advance(0.10)
        #expect(fixture.warps.isEmpty)
    }

    @Test func buttonsBusyModeOffSleepAndReducedMotionCancelCursorFlight() throws {
        for interruption in 0..<5 {
            let fixture = try HoverFixture()
            defer { fixture.close() }
            fixture.model.batCursorAway = true
            fixture.move(to: fixture.point)
            fixture.advance(0.19)
            fixture.advance(0.04)
            let count = fixture.warps.count
            switch interruption {
            case 0: fixture.buttons = true
            case 1: fixture.busy = true
            case 2: fixture.model.batCursorAway = false
            case 3: fixture.model.enabled = false
            default: fixture.model.reduceMotion = true
            }
            fixture.advance(0.02)
            #expect(fixture.model.idleArm == nil)
            #expect(fixture.warps.count == count)
        }
    }

    @Test func reducedMotionNeverFlingsEvenWithBattingEnabled() throws {
        let fixture = try HoverFixture()
        defer { fixture.close() }
        fixture.model.batCursorAway = true
        fixture.model.reduceMotion = true
        fixture.move(to: fixture.point)
        fixture.advance(0.2)
        #expect(fixture.model.idleArm != nil)
        fixture.advance(0.3)
        #expect(fixture.model.idleArm == nil)
        #expect(fixture.warps.isEmpty)
    }

    @Test func warpFailureOrUnobservedPhysicalMovementStopsImmediately() throws {
        for failsWarp in [false, true] {
            let fixture = try HoverFixture()
            defer { fixture.close() }
            fixture.model.batCursorAway = true
            fixture.move(to: fixture.point)
            fixture.advance(0.19)
            let count = fixture.warps.count
            if failsWarp { fixture.warpSucceeds = false }
            else { fixture.point.x += 8 }
            fixture.advance(0.04)
            #expect(fixture.model.idleArm == nil)
            #expect(fixture.warps.count == count)
        }
    }

    @Test func flightStaysOnItsDisplayIncludingNegativeOriginsAndEndsBounded() {
        for frame in [CGRect(x: 0, y: 0, width: 1200, height: 800),
                      CGRect(x: -1920, y: 400, width: 1920, height: 1080),
                      CGRect(x: 1200, y: -700, width: 900, height: 700)] {
            let screen = IdleHoverScreen(frame: frame,
                visibleFrame: CGRect(x: frame.minX, y: frame.minY + 50, width: frame.width, height: frame.height - 74), menuBarHeight: 24)
            for side: CGFloat in [-1, 1] {
                let start = CGPoint(x: frame.midX + side * 50, y: frame.maxY - 50)
                let flight = CursorFlight(start: start, screen: screen)
                #expect(flight.point(at: 0) == start)
                for index in 0...30 {
                    let point = flight.point(at: Double(index) / 100)
                    #expect(screen.visibleFrame.contains(point))
                    #expect(point.y <= start.y)
                }
                #expect(flight.point(at: 10) == flight.destination)
            }
        }
    }
}

@MainActor
private final class HoverFixture {
    let defaults: UserDefaults
    let model: MonsterModel
    let screen = IdleHoverScreen(frame: CGRect(x: 0, y: 0, width: 1200, height: 800),
        visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 776), menuBarHeight: 24)
    var point = CGPoint(x: 600, y: 744)
    var time: TimeInterval = 0
    var buttons = false
    var busy = false
    var warpSucceeds = true
    var warps: [CGPoint] = []
    var controller: IdleHoverController!
    private let suite = "notch-hover-tests.\(UUID().uuidString)"

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        model = MonsterModel(defaults: defaults)
        controller = IdleHoverController(model: model,
            isBusy: { [unowned self] in busy }, pointer: { [unowned self] in point },
            buttonsDown: { [unowned self] in buttons }, screens: { [unowned self] in [screen] },
            warpCursor: { [unowned self] value in
                guard warpSucceeds else { return false }
                warps.append(value); point = value; return true
            }, clock: { [unowned self] in time }, animateAutomatically: false)
    }

    func move(to point: CGPoint) { self.point = point; controller.pointerMoved(at: point) }
    func advance(_ duration: TimeInterval) { time += duration; controller.tick() }
    func close() { controller.stop(); defaults.removePersistentDomain(forName: suite) }
}
