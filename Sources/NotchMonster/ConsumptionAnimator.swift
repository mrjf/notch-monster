import AppKit
import QuartzCore

/// Animates a captured image independently of the real application's minimum
/// window size. All incoming geometry uses AppKit's global bottom-left origin.
@MainActor
final class ConsumptionAnimator {
    @discardableResult
    func yank(
        image: NSImage,
        frame: CGRect,
        grabPoint: CGPoint,
        notch: CGPoint,
        crumple: Bool,
        model: MonsterModel,
        beforeYank: (@MainActor () async -> Bool)? = nil
    ) async -> Bool {
        guard frame.width > 0, frame.height > 0,
              let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }

        let destination = CGRect(x: notch.x - 1, y: notch.y - 1, width: 2, height: 2)
        let panelFrame = frame.union(destination).insetBy(dx: -48, dy: -48)
        let panel = NSPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let surface = NSView(frame: CGRect(origin: .zero, size: panelFrame.size))
        surface.wantsLayer = true
        guard let backingLayer = surface.layer else { return false }
        backingLayer.backgroundColor = NSColor.clear.cgColor
        backingLayer.masksToBounds = false
        panel.contentView = surface

        let picture = CALayer()
        picture.bounds = CGRect(origin: .zero, size: frame.size)
        // Keeping the pointer's image location as the transform anchor makes the
        // hand stay attached while the rest of the screenshot folds around it.
        let grip = CGPoint(x: grabPoint.x - frame.minX, y: grabPoint.y - frame.minY)
        picture.anchorPoint = CGPoint(x: grip.x / frame.width, y: grip.y / frame.height)
        picture.position = CGPoint(x: grabPoint.x - panelFrame.minX, y: grabPoint.y - panelFrame.minY)
        picture.masksToBounds = false
        backingLayer.addSublayer(picture)

        let count = crumple && !model.reduceMotion ? 16 : 1
        let stripWidth = frame.width / CGFloat(count)
        var strips: [CALayer] = []
        var shades: [CALayer] = []
        for index in 0..<count {
            let strip = CALayer()
            strip.bounds = CGRect(x: 0, y: 0, width: stripWidth + 0.4, height: frame.height)
            strip.position = CGPoint(x: stripWidth * (CGFloat(index) + 0.5), y: frame.height / 2)
            strip.contents = bitmap
            strip.contentsGravity = .resize
            strip.contentsRect = CGRect(x: CGFloat(index) / CGFloat(count), y: 0, width: 1 / CGFloat(count), height: 1)
            strip.contentsScale = max(1, CGFloat(bitmap.width) / frame.width)
            strip.minificationFilter = .trilinear
            strip.magnificationFilter = .linear
            strip.isDoubleSided = false
            picture.addSublayer(strip)
            strips.append(strip)

            let shade = CALayer()
            shade.frame = strip.bounds
            shade.backgroundColor = (index.isMultiple(of: 2) ? NSColor.black : NSColor.white).cgColor
            shade.opacity = 0
            strip.addSublayer(shade)
            shades.append(shade)
        }

        model.mood = .chewing
        model.proximity = 1
        model.cursorOffset = CGSize(width: grabPoint.x - notch.x, height: grabPoint.y - notch.y)
        panel.orderFrontRegardless()
        defer {
            panel.orderOut(nil)
            panel.close()
        }

        // Give the initial screenshot a frame to appear before the caller closes
        // the exact captured window. Failed/denied closes leave it untouched.
        try? await Task.sleep(for: .milliseconds(17))
        guard !Task.isCancelled else { return false }
        if let beforeYank, !(await beforeYank()) { return false }
        guard !Task.isCancelled else { return false }

        model.playYankSound(crumple: crumple)
        let duration: CFTimeInterval = model.reduceMotion ? 0.12 : (crumple ? 0.18 : 0.13)
        let start = CACurrentMediaTime()
        while true {
            let t = min(1, CGFloat((CACurrentMediaTime() - start) / duration))
            let pull = 1 - pow(1 - t, 3)
            CATransaction.begin()
            CATransaction.setDisableActions(true)

            if model.reduceMotion {
                picture.opacity = Float(1 - t)
                model.cursorOffset = .zero
            } else {
                let currentGrip = CGPoint(
                    x: grabPoint.x + (notch.x - grabPoint.x) * pull,
                    y: grabPoint.y + (notch.y - grabPoint.y) * pull
                )
                picture.position = CGPoint(x: currentGrip.x - panelFrame.minX, y: currentGrip.y - panelFrame.minY)
                model.cursorOffset = CGSize(width: currentGrip.x - notch.x, height: currentGrip.y - notch.y)

                // Width pinches earlier than height: a broad window becomes a
                // narrow accordion before the whole bundle is swallowed.
                let scaleX = max(0.002, pow(1 - t, crumple ? 1.65 : 0.8))
                let scaleY = max(0.002, pow(1 - t, crumple ? 0.9 : 0.8))
                picture.transform = CATransform3DMakeScale(scaleX, scaleY, 1)
                picture.opacity = Float(min(1, (1 - t) / 0.1))

                if crumple {
                    let fold = sin(min(1, t * 1.35) * .pi / 2)
                    let angle = fold * 1.18
                    let foldedWidth = cos(angle)
                    for (index, strip) in strips.enumerated() {
                        let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
                        let originalX = stripWidth * (CGFloat(index) + 0.5)
                        strip.position = CGPoint(
                            x: grip.x + (originalX - grip.x) * foldedWidth,
                            y: frame.height / 2 + sin(CGFloat(index) * 1.9) * fold * min(18, frame.height * 0.03)
                        )
                        var crease = CATransform3DMakeRotation(direction * angle, 0, 1, 0)
                        crease = CATransform3DRotate(crease, direction * sin(t * .pi) * 0.025, 0, 0, 1)
                        strip.transform = crease
                        shades[index].opacity = Float(fold * (index.isMultiple(of: 2) ? 0.34 : 0.15))
                    }
                }
            }
            CATransaction.commit()

            if t >= 1 { break }
            do { try await Task.sleep(for: .milliseconds(16)) }
            catch { return false }
        }
        model.cursorOffset = .zero
        return true
    }
}
