import AppKit
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

    private let workspace = NSWorkspace.shared
    private var activationObserver: NSObjectProtocol?
    private let browserQueue = DispatchQueue(label: "com.nacifsoftware.keyflow.chrome-url")
    private var lookupGeneration = 0
    private var browserLookupInProgress = false

    func start() {
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
    }

    deinit {
        if let activationObserver {
            workspace.notificationCenter.removeObserver(activationObserver)
        }
    }

    private func update(from application: NSRunningApplication) {
        if application.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        let next = FocusSnapshot(
            appName: application.localizedName,
            bundleIdentifier: application.bundleIdentifier,
            activeURL: nil
        )
        guard next != current else { return }
        current = next
    }

    func readChromeActiveURL(completion: @escaping (BrowserURLResult) -> Void) {
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
                guard let self, self.lookupGeneration == generation,
                      self.current.bundleIdentifier == "com.google.Chrome" else { return }
                completion(result)
            }
        }
    }

    func publishChromeURL(_ url: String?) {
        currentBrowserURL = url
    }

}
