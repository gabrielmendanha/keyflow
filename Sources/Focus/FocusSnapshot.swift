import Foundation

struct FocusSnapshot: Equatable {
    let appName: String?
    let bundleIdentifier: String?
    var activeURL: String?

    static let unknown = FocusSnapshot(appName: nil, bundleIdentifier: nil, activeURL: nil)

    var displayName: String {
        appName ?? bundleIdentifier ?? "No frontmost app"
    }
}
