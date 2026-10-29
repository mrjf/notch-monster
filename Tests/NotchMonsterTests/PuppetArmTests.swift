import AppKit
import SwiftUI
import Testing
@testable import NotchMonster

@MainActor
struct PuppetArmTests {
    private let width = 848
    private let height = 424

    @Test func shallowReachesNeverDrawBehindTheOpeningAndKeepTheHandAtTheCursor() throws {
        for side: CGFloat in [-1, 1] {
            let reach = CGSize(width: side * 140, height: -8)
            let bitmap = try render(reach: reach, extensionAmount: 1)
            #expect(rearPixelCount(bitmap, direction: reach) == 0)
            let cursorX = width / 2 + Int(reach.width)
            #expect(alpha(bitmap, x: cursorX, y: 8) > 0.5)
        }
    }

    @Test func retractingHandAndShaftCannotPeekOutBehindTheNotch() throws {
        for side: CGFloat in [-1, 1] {
            let reach = CGSize(width: side * 140, height: -8)
            for amount: CGFloat in [0.65, 0.4, 0.1] {
                let bitmap = try render(reach: reach, extensionAmount: amount)
                #expect(rearPixelCount(bitmap, direction: reach) == 0)
            }
            let hidden = try render(reach: reach, extensionAmount: 0)
            #expect(totalPixelCount(hidden) == 0)
        }
    }

    private func render(reach: CGSize, extensionAmount: CGFloat) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: PuppetArm(
            reach: reach, direction: reach, extensionAmount: extensionAmount, gripAmount: 0
        ).frame(width: CGFloat(width), height: CGFloat(height)))
        renderer.scale = 1
        renderer.isOpaque = false
        let image = try #require(renderer.cgImage)
        #expect(image.width == width)
        #expect(image.height == height)
        return NSBitmapImageRep(cgImage: image)
    }

    private func alpha(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
        bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    private func rearPixelCount(_ bitmap: NSBitmapImageRep, direction: CGSize) -> Int {
        let length = hypot(direction.width, direction.height)
        let axis = CGPoint(x: direction.width / length, y: -direction.height / length)
        var count = 0
        for y in 0..<height {
            for x in 0..<width {
                let distance = (CGFloat(x) + 0.5 - CGFloat(width) / 2) * axis.x + (CGFloat(y) + 0.5) * axis.y
                // Leave one pixel for antialiasing at the actual aperture edge.
                if distance < -1 && alpha(bitmap, x: x, y: y) > 0.01 { count += 1 }
            }
        }
        return count
    }

    private func totalPixelCount(_ bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for y in 0..<height {
            for x in 0..<width where alpha(bitmap, x: x, y: y) > 0.01 { count += 1 }
        }
        return count
    }
}
