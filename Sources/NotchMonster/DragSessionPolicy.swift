import Foundation

/// Decisions are based on this mouse-down session, never a previous drag.
struct DragSessionPolicy {
    let pasteboardChangeCount: Int

    func hasFreshPasteboard(_ currentChangeCount: Int) -> Bool {
        currentChangeCount != pasteboardChangeCount
    }

    static func windowMoved(from start: CGPoint, to current: CGPoint) -> Bool {
        hypot(current.x - start.x, current.y - start.y) > 3
    }

    static func canCapture(cursor: CGPoint, notch: CGPoint, radius: CGFloat) -> Bool {
        radius > 0 && hypot(cursor.x - notch.x, cursor.y - notch.y) <= radius * 0.95
    }
}

/// A spatial latch, independent of event frequency or pauses. A small outward
/// movement buffer ignores wobble; stopping after release never re-arms a drop.
struct DragAttachmentPolicy {
    private(set) var isAttached = false
    private var radialAnchor: CGFloat?
    private var trackedNotch: CGPoint?
    private let releaseDistance: CGFloat = 5
    private let reattachDistance: CGFloat = 1

    @discardableResult
    mutating func update(cursor: CGPoint, notch: CGPoint, radius: CGFloat) -> Bool {
        if trackedNotch != notch {
            reset()
            trackedNotch = notch
        }
        guard DragSessionPolicy.canCapture(cursor: cursor, notch: notch, radius: radius) else {
            isAttached = false
            radialAnchor = nil
            return false
        }
        let distance = hypot(cursor.x - notch.x, cursor.y - notch.y)
        guard let anchor = radialAnchor else {
            isAttached = true
            radialAnchor = distance
            return true
        }
        if isAttached {
            if distance >= anchor + releaseDistance {
                isAttached = false
                radialAnchor = distance
            } else {
                radialAnchor = min(anchor, distance)
            }
        } else if distance <= anchor - reattachDistance {
            isAttached = true
            radialAnchor = distance
        } else {
            radialAnchor = max(anchor, distance)
        }
        return isAttached
    }

    mutating func reset() {
        isAttached = false
        radialAnchor = nil
        trackedNotch = nil
    }
}
