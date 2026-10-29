import SwiftUI

/// A rigid rod puppet: constant-width straight shaft, fixed palm, curling digits.
/// Fur is deterministic and anchored to the hand, so it never shimmers or wiggles.
struct PuppetArm: View, Animatable {
    var reach: CGSize
    var direction: CGSize
    var extensionAmount: CGFloat
    var gripAmount: CGFloat
    var handOnly = false

    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(extensionAmount, gripAmount) }
        set {
            extensionAmount = newValue.first
            gripAmount = newValue.second
        }
    }

    private let dark = Color(red: 0.20, green: 0.06, blue: 0.29)
    private let purple = Color(red: 0.47, green: 0.18, blue: 0.63)
    private let light = Color(red: 0.69, green: 0.38, blue: 0.82)

    var body: some View {
        Canvas { context, size in
            guard extensionAmount > 0 else { return }
            let vector = CGPoint(x: direction.width, y: -direction.height)
            let length = max(1, hypot(vector.x, vector.y))
            let axis = CGPoint(x: vector.x / length, y: vector.y / length)
            let target = CGPoint(x: reach.width, y: -reach.height)
            let origin = CGPoint(x: size.width / 2, y: 0)
            // Hide everything behind the notch's opening, including the hand
            // while it retracts. A long shaft alone can expose its rear cap
            // on the opposite side of the notch during a shallow reach.
            let extent = hypot(size.width, size.height) + 512
            let normal = CGPoint(x: -axis.y * extent, y: axis.x * extent)
            var opening = Path()
            opening.move(to: CGPoint(x: origin.x + normal.x, y: origin.y + normal.y))
            opening.addLine(to: CGPoint(x: origin.x - normal.x, y: origin.y - normal.y))
            opening.addLine(to: CGPoint(x: origin.x - normal.x + axis.x * extent * 2,
                                        y: origin.y - normal.y + axis.y * extent * 2))
            opening.addLine(to: CGPoint(x: origin.x + normal.x + axis.x * extent * 2,
                                        y: origin.y + normal.y + axis.y * extent * 2))
            opening.closeSubpath()
            context.clip(to: opening)
            // Translate the entire puppet out of the notch. Nothing scales,
            // bends, bounces, or rotates independently of the rigid arm.
            let extensionValue = min(1, max(0, extensionAmount))
            let grip = CGPoint(
                x: origin.x - axis.x * 72 + (target.x + axis.x * 72) * extensionValue,
                y: -axis.y * 72 + (target.y + axis.y * 72) * extensionValue
            )
            context.translateBy(x: grip.x, y: grip.y)
            context.rotate(by: .radians(atan2(axis.y, axis.x) - .pi / 2))
            if !handOnly { drawShaft(in: &context) }
            drawHand(in: &context, curl: min(1, max(0, gripAmount)))
        }
        .clipped()
    }

    private func drawShaft(in context: inout GraphicsContext) {
        let shaft = line(CGPoint(x: 0, y: -430), CGPoint(x: 0, y: -29))
        context.stroke(shaft, with: .color(dark), style: StrokeStyle(lineWidth: 35, lineCap: .round))
        context.stroke(shaft, with: .linearGradient(Gradient(colors: [purple, light.opacity(0.85), purple, dark]), startPoint: CGPoint(x: -17, y: 0), endPoint: CGPoint(x: 18, y: 0)), style: StrokeStyle(lineWidth: 32, lineCap: .round))

        for index in 0..<125 {
            let y = -31 - CGFloat(index) * 3.25
            for side: CGFloat in [-1, 1] {
                let seed = index * 7 + (side < 0 ? 0 : 3)
                let root = CGPoint(x: side * (12 + noise(seed) * 3), y: y)
                let tip = CGPoint(x: side * (17 + noise(seed + 1) * 5), y: y + 4 + noise(seed + 2) * 9)
                context.stroke(tuft(root, tip), with: .color(furColor(seed)), style: StrokeStyle(lineWidth: 0.5 + noise(seed + 3) * 0.45, lineCap: .round))
            }
            let x = (noise(index + 101) - 0.5) * 23
            context.stroke(line(CGPoint(x: x, y: y), CGPoint(x: x + 2, y: y + 5)), with: .color(light.opacity(0.19)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
        }
    }

    private func drawHand(in context: inout GraphicsContext, curl: CGFloat) {
        let palm = Path(roundedRect: CGRect(x: -23, y: -43, width: 46, height: 49), cornerRadius: 19)
        context.fill(palm, with: .color(dark))
        context.fill(Path(roundedRect: CGRect(x: -20, y: -42, width: 41, height: 46), cornerRadius: 18), with: .linearGradient(Gradient(colors: [purple, light.opacity(0.85), purple]), startPoint: CGPoint(x: -25, y: -25), endPoint: CGPoint(x: 26, y: -5)))

        for index in 0..<100 {
            let angle = CGFloat(index) * .pi * 2 / 100
            let nx = cos(angle), ny = sin(angle)
            let root = CGPoint(x: nx * 20, y: -19 + ny * 23)
            let tuftLength = 4 + noise(index + 200) * 5
            let tip = CGPoint(x: root.x + nx * tuftLength + ny * 2, y: root.y + ny * tuftLength - nx * 2)
            context.stroke(tuft(root, tip), with: .color(furColor(index + 200)), style: StrokeStyle(lineWidth: 0.75, lineCap: .round))
        }
        for index in 0..<65 {
            let angle = noise(index + 400) * .pi * 2
            let radius = sqrt(noise(index + 500))
            let point = CGPoint(x: cos(angle) * radius * 18, y: -20 + sin(angle) * radius * 20)
            context.stroke(line(point, CGPoint(x: point.x + 1.5, y: point.y + 4)), with: .color(furColor(index + 600).opacity(0.62)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
        }

        // Three soft fingers and an opposing thumb, with a stationary palm.
        drawFinger(in: &context, start: CGPoint(x: -14, y: -7),
                   control1: blend(CGPoint(x: -19, y: 4), CGPoint(x: -29, y: 13), curl),
                   control2: blend(CGPoint(x: -25, y: 19), CGPoint(x: -22, y: 29), curl),
                   tip: blend(CGPoint(x: -24, y: 29), CGPoint(x: -7, y: -1), curl), seed: 700)
        drawFinger(in: &context, start: CGPoint(x: 0, y: -4),
                   control1: blend(CGPoint(x: 0, y: 10), CGPoint(x: -3, y: 23), curl),
                   control2: blend(CGPoint(x: 0, y: 26), CGPoint(x: 15, y: 26), curl),
                   tip: blend(CGPoint(x: 0, y: 36), CGPoint(x: 4, y: 0), curl), seed: 800)
        drawFinger(in: &context, start: CGPoint(x: 14, y: -8),
                   control1: blend(CGPoint(x: 21, y: 4), CGPoint(x: 31, y: 13), curl),
                   control2: blend(CGPoint(x: 26, y: 17), CGPoint(x: 27, y: 26), curl),
                   tip: blend(CGPoint(x: 26, y: 27), CGPoint(x: 13, y: -3), curl), seed: 900)
        drawFinger(in: &context, start: CGPoint(x: -19, y: -25),
                   control1: blend(CGPoint(x: -34, y: -18), CGPoint(x: -38, y: -12), curl),
                   control2: blend(CGPoint(x: -40, y: -1), CGPoint(x: -27, y: 12), curl),
                   tip: blend(CGPoint(x: -34, y: 10), CGPoint(x: -4, y: 3), curl), seed: 1000)
    }

    private func drawFinger(in context: inout GraphicsContext, start: CGPoint, control1: CGPoint, control2: CGPoint, tip: CGPoint, seed: Int) {
        var finger = Path()
        finger.move(to: start)
        finger.addCurve(to: tip, control1: control1, control2: control2)
        context.stroke(finger, with: .color(dark), style: StrokeStyle(lineWidth: 14, lineCap: .round))
        context.stroke(finger, with: .color(purple), style: StrokeStyle(lineWidth: 11, lineCap: .round))
        for index in 0..<24 {
            let t = CGFloat(index) / 23, u = 1 - t
            let point = CGPoint(
                x: u * u * u * start.x + 3 * u * u * t * control1.x + 3 * u * t * t * control2.x + t * t * t * tip.x,
                y: u * u * u * start.y + 3 * u * u * t * control1.y + 3 * u * t * t * control2.y + t * t * t * tip.y
            )
            let dx = 3 * u * u * (control1.x - start.x) + 6 * u * t * (control2.x - control1.x) + 3 * t * t * (tip.x - control2.x)
            let dy = 3 * u * u * (control1.y - start.y) + 6 * u * t * (control2.y - control1.y) + 3 * t * t * (tip.y - control2.y)
            let magnitude = max(0.01, hypot(dx, dy))
            for side: CGFloat in [-1, 1] {
                let normal = CGPoint(x: -dy / magnitude * side, y: dx / magnitude * side)
                let root = CGPoint(x: point.x + normal.x * 3.8, y: point.y + normal.y * 3.8)
                let length = 6 + noise(seed + index) * 3
                let end = CGPoint(x: point.x + normal.x * length + dx / magnitude * 2, y: point.y + normal.y * length + dy / magnitude * 2)
                context.stroke(tuft(root, end), with: .color(furColor(seed + index)), style: StrokeStyle(lineWidth: 0.65, lineCap: .round))
            }
        }
    }

    private func line(_ from: CGPoint, _ to: CGPoint) -> Path {
        Path { path in path.move(to: from); path.addLine(to: to) }
    }

    private func tuft(_ from: CGPoint, _ to: CGPoint) -> Path {
        Path { path in
            path.move(to: from)
            path.addQuadCurve(to: to, control: CGPoint(x: to.x, y: from.y + (to.y - from.y) * 0.15))
        }
    }

    private func blend(_ from: CGPoint, _ to: CGPoint, _ amount: CGFloat) -> CGPoint {
        CGPoint(x: from.x + (to.x - from.x) * amount, y: from.y + (to.y - from.y) * amount)
    }

    private func noise(_ seed: Int) -> CGFloat {
        let value = sin(Double(seed) * 12.9898 + 78.233) * 43758.5453
        return CGFloat(value - floor(value))
    }

    private func furColor(_ seed: Int) -> Color {
        let shade = noise(seed + 33)
        return shade < 0.25 ? dark.opacity(0.82) : light.opacity(0.4 + shade * 0.55)
    }
}
