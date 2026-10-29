import AppKit
import ApplicationServices

/// AppKit coordinates throughout: each display can have a negative origin.
struct IdleHoverScreen: Equatable {
    var frame: CGRect
    var visibleFrame: CGRect
    var menuBarHeight: CGFloat

    func zone(armLength: CGFloat) -> CGRect {
        let top = frame.maxY - menuBarHeight - 3
        let depth = max(menuBarHeight + 24, min(110, armLength * 0.65))
        return CGRect(x: frame.midX - 68, y: frame.maxY - depth, width: 136, height: top - (frame.maxY - depth))
    }
}

/// A stationary pointer gets one greeting. Only a real move out of the wider
/// area can arm another; the cursor's own flight never calls this policy.
struct IdleHoverPolicy {
    private(set) var armed = true
    private var nextGreeting: TimeInterval = -.infinity

    mutating func enter(point: CGPoint, zone: CGRect, eligible: Bool, now: TimeInterval) -> Bool {
        if !zone.insetBy(dx: -24, dy: -24).contains(point) {
            armed = true
            return false
        }
        guard eligible, armed, zone.contains(point), now >= nextGreeting else { return false }
        armed = false
        nextGreeting = now + 1.5
        return true
    }
}

struct CursorFlight {
    let start: CGPoint
    let destination: CGPoint
    let bounds: CGRect
    static let duration: TimeInterval = 0.30

    init(start: CGPoint, screen: IdleHoverScreen) {
        self.start = start
        bounds = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let distance = min(440, min(screen.frame.width * 0.32, screen.frame.height * 0.48))
        let side: CGFloat = start.x < screen.frame.midX ? -1 : 1
        destination = Self.clamp(CGPoint(x: start.x + side * distance * 0.72, y: start.y - distance), to: bounds)
    }

    func point(at elapsed: TimeInterval) -> CGPoint {
        let t = min(1, max(0, elapsed / Self.duration))
        let progress = CGFloat(1 - pow(1 - t, 3))
        return Self.clamp(CGPoint(x: start.x + (destination.x - start.x) * progress,
                                 y: start.y + (destination.y - start.y) * progress), to: bounds)
    }

    static func userMoved(from expected: CGPoint, to actual: CGPoint) -> Bool {
        hypot(expected.x - actual.x, expected.y - actual.y) > 2
    }

    private static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(bounds.maxX, max(bounds.minX, point.x)), y: min(bounds.maxY, max(bounds.minY, point.y)))
    }
}

struct IdleArmPose {
    let id: UUID
    let screenFrame: CGRect
    var reach: CGSize
    var extensionAmount: CGFloat
}

@MainActor
final class IdleHoverController {
    private enum Kind { case wave, swat }
    private struct Activity {
        let id: UUID
        let kind: Kind
        let screen: IdleHoverScreen
        let started: TimeInterval
        var flight: CursorFlight?
        var flightStarted: TimeInterval?
        var lastWarpedPoint: CGPoint?
    }

    private let model: MonsterModel
    private let isBusy: @MainActor () -> Bool
    private let pointer: @MainActor () -> CGPoint
    private let buttonsDown: @MainActor () -> Bool
    private let screens: @MainActor () -> [IdleHoverScreen]
    private let warpCursor: @MainActor (CGPoint) -> Bool
    private let clock: @MainActor () -> TimeInterval
    private let animateAutomatically: Bool
    private var policy = IdleHoverPolicy()
    private var activity: Activity?
    private var timer: Timer?
    private var monitors: [Any] = []
    private var displayObserver: NSObjectProtocol?

    init(
        model: MonsterModel,
        isBusy: @escaping @MainActor () -> Bool,
        pointer: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation },
        buttonsDown: @escaping @MainActor () -> Bool = { NSEvent.pressedMouseButtons != 0 },
        screens: @escaping @MainActor () -> [IdleHoverScreen] = {
            NSScreen.screens.map { screen in
                IdleHoverScreen(frame: screen.frame, visibleFrame: screen.visibleFrame,
                    menuBarHeight: max(NSStatusBar.system.thickness, max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY)))
            }
        },
        warpCursor: @escaping @MainActor (CGPoint) -> Bool = { point in
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
            // Apple documents that a warp posts no mouse event. Physical
            // mouseMoved events therefore cancel flight without filtering.
            return CGWarpMouseCursorPosition(CGPoint(x: point.x, y: primaryTop - point.y)) == .success
        },
        clock: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        animateAutomatically: Bool = true
    ) {
        self.model = model
        self.isBusy = isBusy
        self.pointer = pointer
        self.buttonsDown = buttonsDown
        self.screens = screens
        self.warpCursor = warpCursor
        self.clock = clock
        self.animateAutomatically = animateAutomatically
        model.onIdleInteractionInvalidated = { [weak self] in self?.cancel() }
    }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel, .keyDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) { monitors.append(monitor) }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            }
    }

    func stop() {
        cancel()
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
    }

    private func handle(_ event: NSEvent) {
        if event.type == .mouseMoved {
            pointerMoved(at: pointer())
        } else if event.type != .keyDown || event.keyCode == 53 {
            cancel()
        }
    }

    /// Called only for real pointer events, never from the animation timer.
    func pointerMoved(at point: CGPoint) {
        if activity?.flight != nil { cancel() }
        guard let screen = screens().first(where: { $0.frame.contains(point) }) else { cancel(); return }
        let zone = screen.zone(armLength: model.armLength)
        if activity != nil, point.y > zone.maxY || !zone.insetBy(dx: -24, dy: -24).contains(point) { cancel() }
        let eligible = model.enabled && !buttonsDown() && !isBusy() && model.mood == .idle && activity == nil
        guard policy.enter(point: point, zone: zone, eligible: eligible, now: clock()) else { return }
        let id = UUID()
        let kind: Kind = model.batCursorAway && !model.reduceMotion ? .swat : .wave
        activity = Activity(id: id, kind: kind, screen: screen, started: clock())
        model.idleArm = IdleArmPose(id: id, screenFrame: screen.frame, reach: .zero, extensionAmount: 0)
        tick()
        if animateAutomatically, activity != nil {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        if model.idleArm?.id == activity?.id { model.idleArm = nil }
        activity = nil
    }

    func tick() {
        guard var current = activity else { return }
        guard model.enabled, !buttonsDown(), !isBusy(), model.mood == .idle,
              model.idleArm?.id == current.id, screens().contains(current.screen) else { cancel(); return }
        if current.kind == .swat && (!model.batCursorAway || model.reduceMotion) { cancel(); return }
        let now = clock(), elapsed = now - current.started
        let point = pointer()
        let zone = current.screen.zone(armLength: model.armLength)
        if current.flight == nil && (point.y > zone.maxY || !zone.insetBy(dx: -24, dy: -24).contains(point)) { cancel(); return }
        let notch = CGPoint(x: current.screen.frame.midX, y: current.screen.frame.maxY)
        var reach: CGSize
        var extensionAmount: CGFloat
        if current.kind == .wave {
            let duration: TimeInterval = model.reduceMotion ? 0.42 : 0.78
            guard elapsed < duration else { cancel(); return }
            let depth = max(current.screen.menuBarHeight + 44, min(94, model.armLength * 0.55))
            let waveTime = min(1, max(0, (elapsed - 0.10) / 0.52))
            let sway = model.reduceMotion ? 0 : sin(waveTime * .pi * 4) * 17
            reach = CGSize(width: sway, height: -depth)
            extensionAmount = CGFloat(min(1, max(0, min(elapsed / 0.10, (duration - elapsed) / 0.10))))
        } else {
            let contactTime: TimeInterval = 0.18
            if elapsed < contactTime {
                let swipe = CGFloat(min(1, max(0, (elapsed - 0.10) / 0.08)))
                let side: CGFloat = point.x < notch.x ? -1 : 1
                reach = CGSize(width: point.x - notch.x - side * 30 * (1 - swipe), height: point.y - notch.y)
                extensionAmount = CGFloat(min(1, elapsed / 0.10))
            } else {
                if current.flight == nil {
                    guard zone.contains(point) else { cancel(); return }
                    current.flight = CursorFlight(start: point, screen: current.screen)
                    current.flightStarted = now
                    current.lastWarpedPoint = point
                }
                guard let flight = current.flight, let started = current.flightStarted,
                      let expected = current.lastWarpedPoint,
                      !CursorFlight.userMoved(from: expected, to: point) else { cancel(); return }
                let flightTime = now - started
                let nextPoint = flight.point(at: flightTime)
                guard warpCursor(nextPoint) else { cancel(); return }
                current.lastWarpedPoint = nextPoint
                let followThrough = CGFloat(min(1, flightTime / 0.07))
                let side: CGFloat = flight.destination.x < flight.start.x ? -1 : 1
                reach = CGSize(width: flight.start.x - notch.x + side * 35 * followThrough,
                               height: flight.start.y - notch.y - 10 * followThrough)
                extensionAmount = CGFloat(max(0, 1 - max(0, flightTime - 0.07) / 0.10))
                if flightTime >= CursorFlight.duration { cancel(); return }
            }
        }
        activity = current
        model.idleArm = IdleArmPose(id: current.id, screenFrame: current.screen.frame, reach: reach, extensionAmount: extensionAmount)
    }
}
