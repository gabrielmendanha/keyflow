import Combine
import Foundation

final class FocusProfileCoordinator: ObservableObject {
    @Published private(set) var statusText = "Waiting for the frontmost app…"
    @Published private(set) var isSettling = false

    private let focusReader: FocusReader
    private let catalog: ProfileCatalogStore
    private var observation: AnyCancellable?
    private var pendingChange: DispatchWorkItem?
    private var chromePollTimer: Timer?

    init(focusReader: FocusReader, catalog: ProfileCatalogStore) {
        self.focusReader = focusReader
        self.catalog = catalog
    }

    func start() {
        guard observation == nil else { return }
        observation = focusReader.$current
            .removeDuplicates()
            .sink { [weak self] focus in self?.scheduleMatch(for: focus) }
    }

    private func scheduleMatch(for focus: FocusSnapshot) {
        pendingChange?.cancel()
        chromePollTimer?.invalidate()
        chromePollTimer = nil
        isSettling = true
        statusText = "Waiting for focus to settle…"

        let change = DispatchWorkItem { [weak self] in
            guard let self, self.focusReader.current == focus else { return }
            if focus.bundleIdentifier == "com.google.Chrome",
               self.catalog.rules.contains(where: { $0.site != nil }) {
                self.focusReader.publishChromeURL(nil)
                self.focusReader.readChromeActiveURL { [weak self] result in
                    guard let self, self.focusReader.current.bundleIdentifier == focus.bundleIdentifier else { return }
                    switch result {
                    case .url(let url):
                        self.focusReader.publishChromeURL(url)
                        var snapshot = self.focusReader.current
                        snapshot.activeURL = url
                        self.applyMatch(for: snapshot)
                        self.beginChromePolling(for: focus)
                    case .permissionDenied:
                        self.focusReader.publishChromeURL(nil)
                        self.applyMatch(for: self.focusReader.current, suffix: " · Chrome Automation permission needed")
                    case .unavailable:
                        self.focusReader.publishChromeURL(nil)
                        self.applyMatch(for: self.focusReader.current)
                        self.beginChromePolling(for: focus)
                    }
                }
            } else {
                self.applyMatch(for: focus)
            }
        }
        pendingChange = change
        DispatchQueue.main.asyncAfter(deadline: .now() + catalog.settle, execute: change)
    }

    private func beginChromePolling(for focus: FocusSnapshot) {
        chromePollTimer?.invalidate()
        chromePollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.focusReader.current.bundleIdentifier == focus.bundleIdentifier else { return }
            self.focusReader.readChromeActiveURL { [weak self] result in
                guard let self, self.focusReader.current.bundleIdentifier == focus.bundleIdentifier else { return }
                switch result {
                case .url(let url):
                    guard self.focusReader.currentBrowserURL != url else { return }
                    self.focusReader.publishChromeURL(url)
                    var snapshot = self.focusReader.current
                    snapshot.activeURL = url
                    self.applyMatch(for: snapshot)
                case .permissionDenied:
                    self.chromePollTimer?.invalidate()
                    self.chromePollTimer = nil
                    self.applyMatch(for: self.focusReader.current,
                                    suffix: " · Chrome Automation permission needed")
                case .unavailable:
                    break
                }
            }
        }
    }

    private func applyMatch(for focus: FocusSnapshot, suffix: String = "") {
        isSettling = false
        if let rule = catalog.rules.first(where: { $0.matchesApp(focus) }),
           catalog.selectAutomatically(profileID: rule.profile) {
            let profileName = catalog.profileName(id: rule.profile) ?? rule.profile
            statusText = "Matched \(profileName) · \(rule.summary)\(suffix)"
            return
        }

        if let defaultProfileID = catalog.defaultProfileID,
           catalog.selectAutomatically(profileID: defaultProfileID) {
            statusText = "Default profile · \(catalog.profileName(id: defaultProfileID) ?? defaultProfileID)\(suffix)"
        } else {
            statusText = "No rule matched · keeping current selection\(suffix)"
        }
    }
}
