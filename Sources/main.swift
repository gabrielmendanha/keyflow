import AppKit
import Foundation
import Darwin

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--validate-catalog" {
    do {
        let catalog = try ProfileCatalogLoader.load(
            catalogURL: URL(fileURLWithPath: CommandLine.arguments[2])
        )
        print("Valid profile catalog: \(catalog.profiles.count) profiles, \(catalog.rules.count) rules")
        exit(EXIT_SUCCESS)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

let application = NSApplication.shared
private let delegate = MenuBarApp()
application.delegate = delegate
application.run()
