// Canvas counterpart of the native app's rigid, fuzzy rod-puppet hand.
// Coordinates are CSS pixels. Call resize() when the canvas's CSS size changes.
// Optional direction:{x,y} locks the shaft angle during a yank; otherwise the
// angle follows origin -> hand and retains its last direction at zero distance.
export class MonsterArm {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    if (!this.ctx) throw new Error("Notch Monster requires a 2D canvas.");
    this.width = 0;
    this.height = 0;
    this.dpr = 1;
    this.axis = { x: 0, y: 1 };
    this._fur = new Map();
    this._last = null;
    this.resize();
  }

  resize() {
    const rect = this.canvas.getBoundingClientRect();
    const width = Math.max(0, rect.width);
    const height = Math.max(0, rect.height);
    const dpr = Math.min(3, Math.max(1, globalThis.devicePixelRatio || 1));
    const bitmapWidth = Math.max(1, Math.round(width * dpr));
    const bitmapHeight = Math.max(1, Math.round(height * dpr));
    const changed = this.canvas.width !== bitmapWidth ||
      this.canvas.height !== bitmapHeight || this.dpr !== dpr ||
      this.width !== width || this.height !== height;
    this.width = width;
    this.height = height;
    this.dpr = dpr;
    if (changed) {
      this.canvas.width = bitmapWidth;
      this.canvas.height = bitmapHeight;
      if (this._last) this.draw(this._last);
    }
    return changed;
  }

  hide() {
    this._last = null;
    this.ctx.setTransform(1, 0, 0, 1, 0, 0);
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
  }

  draw({ origin, hand, curl = 0, visible = 1, scale = 1, direction } = {}) {
    this._last = { origin, hand, curl, visible, scale, direction };
    const ctx = this.ctx;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    if (!(visible > 0) || !origin || !hand || !(scale > 0) ||
        !Number.isFinite(hand.x + hand.y + origin.x + origin.y + scale)) return;

    const dx = hand.x - origin.x;
    const dy = hand.y - origin.y;
    const aimed = direction || { x: dx, y: dy };
    const length = Math.hypot(aimed.x, aimed.y);
    if (length > 0.01) this.axis = { x: aimed.x / length, y: aimed.y / length };
    const shaftLength = Math.max(90, Math.hypot(dx, dy) / scale + 64);
    const grip = Math.min(1, Math.max(0, curl));

    ctx.save();
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.beginPath();
    ctx.rect(0, 0, this.width, this.height);
    ctx.clip();
    // The puppet enters through a fixed aperture, not the canvas boundary.
    // Hide everything behind it, including the hand during retraction. The
    // cut across the shaft is concealed by the notch above this canvas.
    const extent = Math.hypot(this.width, this.height) + Math.hypot(origin.x, origin.y) + 1;
    const side = { x: -this.axis.y * extent, y: this.axis.x * extent };
    const front = { x: this.axis.x * extent, y: this.axis.y * extent };
    ctx.beginPath();
    ctx.moveTo(origin.x - side.x, origin.y - side.y);
    ctx.lineTo(origin.x + side.x, origin.y + side.y);
    ctx.lineTo(origin.x + side.x + front.x, origin.y + side.y + front.y);
    ctx.lineTo(origin.x - side.x + front.x, origin.y - side.y + front.y);
    ctx.closePath();
    ctx.clip();
    ctx.globalAlpha = Math.min(1, visible);
    ctx.translate(hand.x, hand.y);
    ctx.rotate(Math.atan2(this.axis.y, this.axis.x) - Math.PI / 2);
    ctx.scale(scale, scale);
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    this._shaft(ctx, shaftLength);
    this._palm(ctx);
    this._fingers(ctx, grip);
    ctx.restore();
  }

  _shaft(ctx, length) {
    this._line(ctx, 0, -length, 0, -29, "#330f4a", 35);
    const gradient = ctx.createLinearGradient(-17, 0, 18, 0);
    gradient.addColorStop(0, "#782ea1");
    gradient.addColorStop(0.34, "rgba(176,97,209,.95)");
    gradient.addColorStop(0.67, "#782ea1");
    gradient.addColorStop(1, "#330f4a");
    this._line(ctx, 0, -length, 0, -29, gradient, 32);

    // Bound work even if the host page requests an unusually long arm.
    const count = Math.min(500, Math.ceil((length - 29) / 3.25));
    for (let index = 0; index < count; index++) {
      const y = -31 - index * 3.25;
      for (const side of [-1, 1]) {
        const seed = index * 7 + (side < 0 ? 0 : 3);
        const rootX = side * (12 + noise(seed) * 3);
        const tipX = side * (17 + noise(seed + 1) * 5);
        const tipY = y + 4 + noise(seed + 2) * 9;
        this._tuft(ctx, rootX, y, tipX, tipY, this._furColor(seed), 0.5 + noise(seed + 3) * 0.45);
      }
      const x = (noise(index + 101) - 0.5) * 23;
      this._line(ctx, x, y, x + 2, y + 5, "rgba(176,97,209,.19)", 0.8);
    }
  }

  _palm(ctx) {
    this._roundedRect(ctx, -23, -43, 46, 49, 19, "#330f4a");
    const gradient = ctx.createLinearGradient(-25, -25, 26, -5);
    gradient.addColorStop(0, "#782ea1");
    gradient.addColorStop(0.43, "rgba(176,97,209,.95)");
    gradient.addColorStop(1, "#782ea1");
    this._roundedRect(ctx, -20, -42, 41, 46, 18, gradient);

    for (let index = 0; index < 100; index++) {
      const angle = index * Math.PI * 2 / 100;
      const nx = Math.cos(angle), ny = Math.sin(angle);
      const x = nx * 20, y = -19 + ny * 23;
      const length = 4 + noise(index + 200) * 5;
      this._tuft(ctx, x, y, x + nx * length + ny * 2, y + ny * length - nx * 2, this._furColor(index + 200), 0.75);
    }
    for (let index = 0; index < 65; index++) {
      const angle = noise(index + 400) * Math.PI * 2;
      const radius = Math.sqrt(noise(index + 500));
      const x = Math.cos(angle) * radius * 18;
      const y = -20 + Math.sin(angle) * radius * 20;
      ctx.save();
      ctx.globalAlpha *= 0.62;
      this._line(ctx, x, y, x + 1.5, y + 4, this._furColor(index + 600), 0.8);
      ctx.restore();
    }
  }

  _fingers(ctx, curl) {
    this._finger(ctx, [-14, -7], mix([-19, 4], [-29, 13], curl),
      mix([-25, 19], [-22, 29], curl), mix([-24, 29], [-7, -1], curl), 700);
    this._finger(ctx, [0, -4], mix([0, 10], [-3, 23], curl),
      mix([0, 26], [15, 26], curl), mix([0, 36], [4, 0], curl), 800);
    this._finger(ctx, [14, -8], mix([21, 4], [31, 13], curl),
      mix([26, 17], [27, 26], curl), mix([26, 27], [13, -3], curl), 900);
    this._finger(ctx, [-19, -25], mix([-34, -18], [-38, -12], curl),
      mix([-40, -1], [-27, 12], curl), mix([-34, 10], [-4, 3], curl), 1000);
  }

  _finger(ctx, start, c1, c2, tip, seed) {
    ctx.beginPath();
    ctx.moveTo(...start);
    ctx.bezierCurveTo(...c1, ...c2, ...tip);
    ctx.strokeStyle = "#330f4a";
    ctx.lineWidth = 14;
    ctx.stroke();
    const gradient = ctx.createLinearGradient(start[0] - 6, start[1], start[0] + 7, tip[1]);
    gradient.addColorStop(0, "#69228d");
    gradient.addColorStop(0.44, "#a25ac0");
    gradient.addColorStop(1, "#782ea1");
    ctx.strokeStyle = gradient;
    ctx.lineWidth = 11;
    ctx.stroke();

    for (let index = 0; index < 24; index++) {
      const t = index / 23, u = 1 - t;
      const x = u ** 3 * start[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t ** 3 * tip[0];
      const y = u ** 3 * start[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t ** 3 * tip[1];
      const dx = 3 * u * u * (c1[0] - start[0]) + 6 * u * t * (c2[0] - c1[0]) + 3 * t * t * (tip[0] - c2[0]);
      const dy = 3 * u * u * (c1[1] - start[1]) + 6 * u * t * (c2[1] - c1[1]) + 3 * t * t * (tip[1] - c2[1]);
      const magnitude = Math.max(0.01, Math.hypot(dx, dy));
      for (const side of [-1, 1]) {
        const nx = -dy / magnitude * side, ny = dx / magnitude * side;
        const length = 6 + noise(seed + index) * 3;
        this._tuft(ctx, x + nx * 3.8, y + ny * 3.8,
          x + nx * length + dx / magnitude * 2,
          y + ny * length + dy / magnitude * 2,
          this._furColor(seed + index), 0.65);
      }
    }
  }

  _furColor(seed) {
    if (!this._fur.has(seed)) {
      const shade = noise(seed + 33);
      this._fur.set(seed, shade < 0.25 ? "rgba(51,15,74,.82)" : `rgba(176,97,209,${0.4 + shade * 0.55})`);
    }
    return this._fur.get(seed);
  }

  _line(ctx, x1, y1, x2, y2, color, width) {
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.lineTo(x2, y2);
    ctx.strokeStyle = color;
    ctx.lineWidth = width;
    ctx.stroke();
  }

  _tuft(ctx, x1, y1, x2, y2, color, width) {
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.quadraticCurveTo(x2, y1 + (y2 - y1) * 0.15, x2, y2);
    ctx.strokeStyle = color;
    ctx.lineWidth = width;
    ctx.stroke();
  }

  _roundedRect(ctx, x, y, width, height, radius, fill) {
    ctx.beginPath();
    ctx.roundRect(x, y, width, height, radius);
    ctx.fillStyle = fill;
    ctx.fill();
  }
}

function noise(seed) {
  const value = Math.sin(seed * 12.9898 + 78.233) * 43758.5453;
  return value - Math.floor(value);
}

function mix(from, to, amount) {
  return [from[0] + (to[0] - from[0]) * amount, from[1] + (to[1] - from[1]) * amount];
}
