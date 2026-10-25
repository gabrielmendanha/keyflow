import AppKit
import ApplicationServices
import Combine
import Foundation

enum BrowserURLResult {
    case url(String)
    case unavailable
    case permissionDenied
}

final class FocusReader: ObservableObject {
    @Published private(set) var current = FocusSnapshot.unknown
    @Published private(set) var currentBrowserURL: String?
    @Published private(set) var requiresWindowTitleAccess = false
    @Published private(set) var needsAccessibilityPermission = false

    private let workspace = NSWorkspace.shared
    private var activationObserver: NSObjectProtocol?
    private let browserQueue = DispatchQueue(label: "com.nacifsoftware.keyflow.chrome-url")
    private var lookupGeneration = 0
    private var browserLookupInProgress = false
    private var windowTitleTimer: Timer?

    func start(requiresWindowTitleAccess: Bool = false) {
        self.requiresWindowTitleAccess = requiresWindowTitleAccess
        guard activationObserver == nil else { return }
        activationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: workspace,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            self?.update(from: application)
        }
        if let frontmost = workspace.frontmostApplication {
            update(from: frontmost)
        }
        guard requiresWindowTitleAccess else { return }
        checkAccessibilityPermission(prompt: true)
        windowTitleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshWindowTitle()
        }
        refreshWindowTitle()
    }

    deinit {
        if let activationObserver {
            workspace.notificationCenter.removeObserver(activationObserver)
        }
        windowTitleTimer?.invalidate()
    }

    private func update(from application: NSRunningApplication) {
        if application.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        let next = FocusSnapshot(
            appName: application.localizedName,
            bundleIdentifier: application.bundleIdentifier,
            processIdentifier: application.processIdentifier,
            activeURL: nil,
            windowTitle: nil
        )
        guard next != current else { return }
        current = next
        refreshWindowTitle()
    }

    func readChromeActiveURL(
        requireChromeFrontmost: Bool = true,
        completion: @escaping (BrowserURLResult) -> Void
    ) {
        guard !browserLookupInProgress else { return }
        browserLookupInProgress = true
        lookupGeneration += 1
        let generation = lookupGeneration
        browserQueue.async { [weak self] in
            let script = NSAppleScript(source: """
            with timeout of 2 seconds
                tell application id "com.google.Chrome" to get URL of active tab of front window
            end timeout
            """)
            var errorInfo: NSDictionary?
            let value = script?.executeAndReturnError(&errorInfo).stringValue
            let errorNumber = errorInfo?[NSAppleScript.errorNumber] as? Int
            let result: BrowserURLResult
            if errorNumber == -1743 {
                result = .permissionDenied
            } else if let value, URL(string: value)?.scheme != nil {
                result = .url(value)
            } else {
                result = .unavailable
            }
            DispatchQueue.main.async {
                self?.browserLookupInProgress = false
                guard let self, self.lookupGeneration == generation else { return }
                if requireChromeFrontmost && self.current.bundleIdentifier != "com.google.Chrome" {
                    return
                }
                completion(result)
            }
        }
    }

    func publishChromeURL(_ url: String?) {
        currentBrowserURL = url
    }

    private func checkAccessibilityPermission(prompt: Bool) {
        let trusted: Bool
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
        } else {
            trusted = AXIsProcessTrusted()
        }
        needsAccessibilityPermission = !trusted
    }

    private func refreshWindowTitle() {
        guard requiresWindowTitleAccess else { return }
        checkAccessibilityPermission(prompt: false)
        guard !needsAccessibilityPermission else {
            updateWindowTitle(nil)
            return
        }
        guard let processIdentifier = current.processIdentifier else { return }

        let appElement = AXUIElementCreateApplication(processIdentifier)
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        guard result == .success, let focusedWindow,
              CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() else {
            updateWindowTitle(nil)
            return
        }

        let windowElement = unsafeBitCast(focusedWindow, to: AXUIElement.self)
        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            windowElement,
            kAXTitleAttribute as CFString,
            &titleValue
        )
        let title = titleResult == .success ? titleValue as? String : nil
        updateWindowTitle(title)
    }

    private func updateWindowTitle(_ title: String?) {
        guard current.windowTitle != title else { return }
        var snapshot = current
        snapshot.windowTitle = title
        current = snapshot
    }

}
