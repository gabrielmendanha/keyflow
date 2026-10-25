import AppKit
import Combine
import SwiftUI

final class MenuBarApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var outsideClickMonitor: Any?
    private var status = DeviceStatus()
    private var catalog: ProfileCatalogStore!
    private var focusReader: FocusReader!
    private var focusCoordinator: FocusProfileCoordinator!
    private var profileApplication: ProfileApplicationCoordinator!
    private var monitor: PadMonitor!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = KeyflowMenuBarIcon.image
            button.image?.accessibilityDescription = "Keyflow Macropad"
            button.target = self
            button.action = #selector(togglePanel)
            button.toolTip = "Keyflow — Macropad status"
        }

        catalog = ProfileCatalogStore()
        focusReader = FocusReader()
        focusReader.start()
        focusCoordinator = FocusProfileCoordinator(focusReader: focusReader, catalog: catalog)
        focusCoordinator.start()
        profileApplication = ProfileApplicationCoordinator(status: status, catalog: catalog)
        profileApplication.start()
        let content = KeyflowPanelView(
            status: status,
            catalog: catalog,
            focusCoordinator: focusCoordinator
        ) { NSApp.terminate(nil) }
        let controller = NSHostingController(rootView: content)
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 236),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = controller
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        installOutsideClickMonitor()

        monitor = PadMonitor(status: status)
        monitor.start()
        updateMenuBarIndicator()

        status.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateMenuBarIndicator() }
        }.store(in: &cancellables)

        if CommandLine.arguments.contains("--preview"), let button = statusItem.button {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak button] in
                guard let self, let button else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.showPanel(from: button)
            }
        }
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel(from: button)
        }
    }

    private func showPanel(from button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let panelSize = panel.frame.size
        let visibleFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let proposedX = buttonRect.midX - panelSize.width / 2
        let x = min(max(proposedX, visibleFrame.minX + 8), visibleFrame.maxX - panelSize.width - 8)
        let y = buttonRect.minY - panelSize.height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func installOutsideClickMonitor() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.panel.isVisible else { return }
                let point = NSEvent.mouseLocation
                if self.panel.frame.contains(point) { return }
                if let button = self.statusItem.button, let window = button.window {
                    let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
                    if buttonFrame.contains(point) { return }
                }
                self.panel.orderOut(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
    }

    private func updateMenuBarIndicator() {
        statusItem.button?.toolTip = status.isConnected
            ? "Keyflow — Macropad connected"
            : "Keyflow — Macropad not connected"
    }

    private var cancellables = Set<AnyCancellable>()
}
