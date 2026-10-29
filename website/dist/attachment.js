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

// Capture is a commitment. Only observed outward pointer MOVEMENT can revoke
// it: a full hand-width, over multiple samples and at least 80 ms. Mouse-up,
// stationary samples and the arm's animation never make that decision.
export class CaptureGesture {
  constructor(releaseDistance = 48, reattachDistance = 1) {
    this.releaseDistance = releaseDistance;
    this.reattachDistance = reattachDistance;
    this.reset();
  }
  reset() {
    this.attached = false; this.withdrawn = false; this.previous = null;
    this.closest = Infinity; this.farthest = 0;
    this.outwardSince = null; this.outwardSamples = 0;
    this.outwardFrom = 0; this.lastOutwardAt = -Infinity;
  }
  update(point, origin, radius, now) {
    const previous = this.previous;
    this.previous = {...point};
    const distance = Math.hypot(point.x - origin.x, point.y - origin.y);
    const previousDistance = previous ? Math.hypot(previous.x - origin.x, previous.y - origin.y) : distance;
    const inReach = point.y >= origin.y && distance <= radius;
    if (this.attached) {
      if (distance < this.closest || distance < previousDistance - .5) {
        this.closest = Math.min(this.closest, distance);
        this.outwardSince = null; this.outwardSamples = 0;
      } else if (distance > previousDistance + .01) {
        if (this.outwardSince === null || now - this.lastOutwardAt > 120) {
          this.outwardSince = now; this.outwardSamples = 0;
          this.outwardFrom = previousDistance;
        }
        this.lastOutwardAt = now;
        this.outwardSamples++;
        const clearRetreat = distance - this.outwardFrom >= this.releaseDistance &&
          this.outwardSamples >= 2 && now - this.outwardSince >= 80;
        const farEscape = distance > radius + 240 && distance - this.closest >= 160;
        if (clearRetreat || farEscape) {
          this.attached = false; this.withdrawn = true; this.farthest = distance;
        }
      }
      return this.attached;
    }
    if (this.withdrawn) {
      this.farthest = Math.max(this.farthest, distance);
      if (!inReach || distance > this.farthest - this.reattachDistance) return false;
    } else {
      const swept = previous && point.y >= origin.y - 160 && distance <= radius + 240 &&
        segmentOffer(previous, point, origin, radius) !== null;
      if (!inReach && !swept) return false;
    }
    this.attached = true; this.withdrawn = false; this.closest = distance;
    this.outwardSince = null; this.outwardSamples = 0;
    return true;
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

// A confirmed retreat vetoes the drop. Otherwise a committed grab is enough;
// no animation frame, dwell timer, or final pointerup coordinate can revoke it.
export function canFeedOnRelease({attached, withdrawn = false, readyPoint, phase, hand, point, scale = 1}) {
  if (withdrawn) return false;
  return attached || Boolean(readyPoint) || ((phase === 'reaching' || phase === 'retreating') &&
    Math.hypot(point.x - hand.x, point.y - hand.y) <= 36 * scale);
}
