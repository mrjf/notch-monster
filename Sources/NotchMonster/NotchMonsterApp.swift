import AppKit
import SwiftUI

@main
struct NotchMonsterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(model: appDelegate.model)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = MonsterModel()
    private var overlayController: OverlayController?
    private var statusItem: NSStatusItem?
    private var windowWatcher: WindowDragWatcher?
    private var idleHover: IdleHoverController?
    private var settingsWindowController: NSWindowController?
    private let animator = ConsumptionAnimator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        overlayController = OverlayController(model: model)
        overlayController?.install()
        windowWatcher = WindowDragWatcher(model: model, animator: animator) { [weak self] point in
            self?.overlayController?.trackFileDrag(at: point)
        }
        model.onFileConsumed = { [weak self] icon, cursor, notch in
            self?.windowWatcher?.consumeFile(icon: icon, cursor: cursor, notch: notch)
        }
        windowWatcher?.start()
        idleHover = IdleHoverController(model: model) { [weak self] in
            guard let self else { return true }
            return self.windowWatcher?.isBusy == true || self.overlayController?.hasActiveFileDrag == true
        }
        idleHover?.start()
        installMenuBarItem()
        openSettings()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        idleHover?.stop()
        windowWatcher?.stop()
    }

    private func installMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            icon.size = NSSize(width: 18, height: 18)
            icon.accessibilityDescription = "Notch Monster"
            item.button?.image = icon
        } else {
            item.button?.image = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: "Notch Monster")
        }
        item.button?.toolTip = "Notch Monster — Settings"
        let menu = NSMenu()
        menu.addItem(withTitle: "Notch Monster is awake", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(withTitle: "Quit Notch Monster", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc func openSettings() {
        if settingsWindowController == nil {
            let content = NSHostingView(rootView: SettingsView(model: model))
            content.sizingOptions = .standardBounds
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: content.fittingSize),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Notch Monster Settings"
            window.isReleasedWhenClosed = false
            window.contentView = content
            window.center()
            settingsWindowController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }
}
