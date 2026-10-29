import AppKit
import SwiftUI

@MainActor
@Observable
final class MonsterModel {
    enum Mood { case idle, curious, reaching, chewing, pleased, error }

    var mood: Mood = .idle
    var proximity: CGFloat = 0
    var cursorOffset: CGSize = .zero
    var message = "Drag a file or window toward the notch"
    var enabled = true {
        didSet {
            if !enabled { reset(); soundPlayer.stop() }
        }
    }
    var closeWindows = true
    static let armLengthRange: ClosedRange<CGFloat> = 80...360
    private var storedArmLength: CGFloat
    var armLength: CGFloat {
        get { storedArmLength }
        set {
            storedArmLength = Self.validArmLength(newValue)
            defaults.set(Double(storedArmLength), forKey: "armLength")
            onArmLengthChanged?()
        }
    }
    var captureRadius: CGFloat { armLength }
    var reduceMotion = false {
        didSet { if oldValue != reduceMotion { onIdleInteractionInvalidated?() } }
    }
    var batCursorAway: Bool {
        didSet {
            defaults.set(batCursorAway, forKey: "batCursorAway")
            if oldValue != batCursorAway { onIdleInteractionInvalidated?() }
        }
    }
    var idleArm: IdleArmPose?
    var fileAction: FileDropAction {
        didSet { defaults.set(fileAction.rawValue, forKey: "fileDropAction") }
    }
    var soundEffectsEnabled: Bool {
        didSet {
            defaults.set(soundEffectsEnabled, forKey: "soundEffectsEnabled")
            if !soundEffectsEnabled { soundPlayer.stop() }
        }
    }
    var soundSet: MonsterSoundSet {
        didSet {
            defaults.set(soundSet.rawValue, forKey: "soundSet")
            if oldValue != soundSet {
                soundPlayer.stop()
                soundPlayer.prepare(set: soundSet)
            }
        }
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let soundPlayer: any MonsterSoundPlaying
    @ObservationIgnored private let soundClock: @MainActor () -> TimeInterval
    @ObservationIgnored private var handWasShowing = false
    @ObservationIgnored private var lastReachSound: TimeInterval = -.infinity
    @ObservationIgnored var sendFilesToRaycast: @MainActor ([URL]) throws -> Void = RaycastHandoff.send
    @ObservationIgnored var onFileConsumed: ((NSImage, CGPoint, CGPoint) -> Void)?
    @ObservationIgnored var onArmLengthChanged: (() -> Void)?
    @ObservationIgnored var onIdleInteractionInvalidated: (() -> Void)?
    private var feedbackTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        soundPlayer: (any MonsterSoundPlaying)? = nil,
        soundClock: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.defaults = defaults
        self.soundPlayer = soundPlayer ?? MonsterSoundPlayer()
        self.soundClock = soundClock
        storedArmLength = Self.validArmLength(defaults.object(forKey: "armLength") == nil ? 170 : CGFloat(defaults.double(forKey: "armLength")))
        fileAction = FileDropAction(rawValue: defaults.string(forKey: "fileDropAction") ?? "") ?? .trash
        batCursorAway = defaults.bool(forKey: "batCursorAway")
        soundEffectsEnabled = defaults.bool(forKey: "soundEffectsEnabled")
        soundSet = MonsterSoundSet(rawValue: defaults.string(forKey: "soundSet") ?? "") ?? .fuzzy
        self.soundPlayer.prepare(set: soundSet)
    }

    private static func validArmLength(_ value: CGFloat) -> CGFloat {
        value.isFinite ? min(armLengthRange.upperBound, max(armLengthRange.lowerBound, value)) : 170
    }

    func approach(cursor: CGPoint, center: CGPoint, dragging: Bool) {
        onIdleInteractionInvalidated?()
        idleArm = nil
        feedbackTask?.cancel()
        guard enabled else { reset(); return }
        let dx = cursor.x - center.x
        let dy = cursor.y - center.y
        let distance = hypot(dx, dy)
        cursorOffset = CGSize(width: dx, height: dy)
        proximity = max(0, min(1, 1 - distance / captureRadius))
        mood = dragging ? (proximity > 0.16 ? .reaching : .curious) : .idle
        message = proximity > 0.72 ? "Release to feed me" : "Come closer…"
        let showing = dragging && proximity > 0.05
        if showing && !handWasShowing && soundEffectsEnabled {
            let now = soundClock()
            if now - lastReachSound >= 0.25 {
                soundPlayer.play(.reach, set: soundSet)
                lastReachSound = now
            }
        }
        handWasShowing = showing
    }

    /// Called only after a file action or the captured window's close succeeds.
    func playYankSound(crumple: Bool) {
        guard enabled, soundEffectsEnabled else { return }
        soundPlayer.play(crumple ? .window : .file, set: soundSet)
    }

    func previewSound() {
        guard soundEffectsEnabled else { return }
        soundPlayer.play(.window, set: soundSet)
    }

    func consume(_ label: String) {
        reset()
        message = "Consumed \(label)"
    }

    func fail(_ text: String) {
        soundPlayer.stop()
        handWasShowing = false
        mood = .error
        message = text
        feedbackTask?.cancel()
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            reset()
        }
    }

    func reset() {
        onIdleInteractionInvalidated?()
        idleArm = nil
        feedbackTask?.cancel()
        handWasShowing = false
        mood = .idle
        proximity = 0
        cursorOffset = .zero
        message = "Drag a file or window toward the notch"
    }
}
