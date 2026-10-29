// Five pixels of outward travel forgive a small wobble; one pixel inward
// reattaches promptly after a deliberate retreat. This is distance, not time.
// Track the closest attached point, or the farthest detached point, so slow
// movement accumulates and a reversal is measured from the actual extremum.
export class DirectionalAttachment {
  constructor(releaseDistance = 5, reattachDistance = 1) {
    this.releaseDistance = releaseDistance;
    this.reattachDistance = reattachDistance;
    this.reset();
  }

  reset() {
    this.anchor = null;
    this.attached = false;
  }

  update(distance, inReach) {
    if (!inReach) {
      this.reset();
    } else if (this.anchor === null) {
      this.anchor = distance;
      this.attached = true;
    } else if (this.attached) {
      this.anchor = Math.min(this.anchor, distance);
      if (distance >= this.anchor + this.releaseDistance) {
        this.attached = false;
        this.anchor = distance;
      }
    } else {
      this.anchor = Math.max(this.anchor, distance);
      if (distance <= this.anchor - this.reattachDistance) {
        this.attached = true;
        this.anchor = distance;
      }
    }
    return this.attached;
  }
}

// Pointer events can skip straight across the notch during a fast toss. Test
// the whole traveled segment, then hold through its forward follow-through.
// Reversing and backing away still uses the normal hand-width release rule.
export class CaptureGesture {
  constructor(releaseDistance = 36, reattachDistance = 1) {
    this.policy = new DirectionalAttachment(releaseDistance, reattachDistance);
    this.reset();
  }
  get attached() { return this.policy.attached; }
  reset() {
    this.policy.reset(); this.previous = null;
    this.entered = -Infinity; this.incoming = {x: 0, y: 0};
  }
  update(point, origin, radius, now) {
    const previous = this.previous;
    this.previous = {...point};
    const distance = Math.hypot(point.x - origin.x, point.y - origin.y);
    const movement = previous ? {x: point.x - previous.x, y: point.y - previous.y} : {x: 0, y: 0};
    const wasAttached = this.attached;
    const inReach = point.y >= origin.y + (wasAttached ? -160 : 0) &&
      distance <= radius + (wasAttached ? 160 : 0);
    const forward = movement.x * this.incoming.x + movement.y * this.incoming.y > 0;
    const followThrough = wasAttached && now - this.entered <= 180 && forward &&
      point.y >= origin.y - 160 && distance <= radius + 160;
    if (followThrough) {
      // The hand follows the toss. Measure any later backing-off from where
      // it caught the item, so a tiny wobble after overshoot cannot detach it.
      this.policy.anchor = distance;
      return true;
    }
    let accepted = this.policy.update(distance, inReach);
    if (!accepted && !wasAttached && this.policy.anchor === null && previous &&
        point.y >= origin.y - 160 && distance <= radius + 160) {
      const hit = segmentOffer(previous, point, origin, radius);
      if (hit !== null) accepted = this.policy.update(distance, true);
    }
    if (accepted && !wasAttached) {
      this.entered = now; this.incoming = movement;
    }
    return accepted;
  }
}

function segmentOffer(start, end, origin, radius) {
  const dx = end.x - start.x, dy = end.y - start.y;
  const lengthSquared = dx * dx + dy * dy;
  if (!lengthSquared) return null;
  let low = 0, high = 1;
  // Only the part on or below the desktop's top edge can offer an item.
  if (dy === 0 && start.y < origin.y) return null;
  if (dy > 0) low = Math.max(0, (origin.y - start.y) / dy);
  if (dy < 0) high = Math.min(1, (origin.y - start.y) / dy);
  if (low > high) return null;
  const t = Math.max(low, Math.min(high, ((origin.x - start.x) * dx + (origin.y - start.y) * dy) / lengthSquared));
  const distance = Math.hypot(start.x + dx * t - origin.x, start.y + dy * t - origin.y);
  return distance <= radius ? distance : null;
}

// The last pointermove owns grab intent. Pointerup can contain a small extra
// movement before the hand has even painted; that must not revoke a ready
// grab. Actual outward pointermove still detaches and removes this allowance.
// A large release-only jump remains an escape, even if it ends within reach.
export function canFeedOnRelease({attached, readyPoint, phase, hand, point, scale = 1}) {
  const readyOnRelease = readyPoint && Math.hypot(point.x - readyPoint.x, point.y - readyPoint.y) <= 48 * scale;
  // Open fingers can still touch the item during the first part of retreat.
  return Boolean(readyOnRelease) || attached || ((phase === 'reaching' || phase === 'retreating') &&
    Math.hypot(point.x - hand.x, point.y - hand.y) <= 36 * scale);
}
