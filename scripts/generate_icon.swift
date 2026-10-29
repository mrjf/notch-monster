import AppKit
import SwiftUI

// Render the app's actual hand artwork, with no tile, notch, or substitute logo.
@main
struct GenerateIcon {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let resources = root.appendingPathComponent("Resources")
        let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("NotchMonster-\(UUID().uuidString).iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: iconset) }
        for size in [16, 32, 128, 256, 512] {
            try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
            try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
        }
        try render(1024).write(to: resources.appendingPathComponent("AppIcon.png"))
        try render(64).write(to: root.appendingPathComponent("website/dist/assets/favicon.png"))
        let tool = Process()
        tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        tool.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
        try tool.run(); tool.waitUntilExit()
        guard tool.terminationStatus == 0 else { fatalError("iconutil failed") }
        print(resources.appendingPathComponent("AppIcon.icns").path)
    }

    @MainActor static func render(_ size: Int) throws -> Data {
        let hand = PuppetArm(reach: CGSize(width: 0, height: -55),
            direction: CGSize(width: 0, height: -1), extensionAmount: 1,
            gripAmount: 0, handOnly: true).frame(width: 108, height: 108)
        let renderer = ImageRenderer(content: hand)
        renderer.scale = CGFloat(size) / 108
        renderer.isOpaque = false
        guard let image = renderer.cgImage else { fatalError("Hand rendering failed") }
        precondition(image.width == size && image.height == size)
        let bitmap = NSBitmapImageRep(cgImage: image)
        return bitmap.representation(using: .png, properties: [:])!
    }
}
