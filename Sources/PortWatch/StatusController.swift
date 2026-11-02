import SwiftUI

/// Status item + borderless panel. Replaces MenuBarExtra, whose system panel can't be removed or re-rounded.
@MainActor final class StatusController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = PortStore()
    private var item: NSStatusItem!
    private var panel: NSPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // menu bar only: no Dock icon, no Cmd-Tab

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = PortWatchApp.menuBarIcon
        item.button?.setAccessibilityLabel("PortWatch")
        item.button?.target = self
        item.button?.action = #selector(toggle)

        let host = NSHostingController(rootView: ContentView(store: store))
        host.sizingOptions = .preferredContentSize  // panel follows the content as rows come and go
        panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.contentViewController = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
    }

    @objc func toggle() {
        panel.isVisible ? panel.orderOut(nil) : open()
    }

    func open() {
        place()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        item.button?.highlight(true)
        DispatchQueue.main.async { self.panel.invalidateShadow() }  // shadow must follow the rounded corners
    }

    /// Hang the panel below the status item, clamped to the screen.
    private func place() {
        guard let button = item.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size == .zero ? panel.contentViewController!.view.fittingSize : panel.frame.size
        let screen = buttonWindow.screen?.visibleFrame ?? .infinite
        let x = min(max(anchor.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: anchor.minY - size.height - 6, width: size.width, height: size.height), display: true)
    }

    // Content resizes keep the bottom-left fixed; re-pin the top under the menu bar.
    func windowDidResize(_ notification: Notification) {
        if panel.isVisible { place(); panel.invalidateShadow() }
    }

    // Clicking anywhere else (or Esc) dismisses, like a menu.
    func windowDidResignKey(_ notification: Notification) {
        panel.orderOut(nil)
        item.button?.highlight(false)
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }  // borderless panels refuse key by default; we need ⌘Q and Esc
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }  // Esc; ordering out resigns key, which unhighlights
}


