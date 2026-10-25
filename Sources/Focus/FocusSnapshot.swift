import Foundation

struct FocusSnapshot: Equatable {
    let appName: String?
    let bundleIdentifier: String?
    let processIdentifier: pid_t?
    var activeURL: String?
    var windowTitle: String?

    static let unknown = FocusSnapshot(
        appName: nil,
        bundleIdentifier: nil,
        processIdentifier: nil,
        activeURL: nil,
        windowTitle: nil
    )

    var displayName: String {
        appName ?? bundleIdentifier ?? "No frontmost app"
    }
}
