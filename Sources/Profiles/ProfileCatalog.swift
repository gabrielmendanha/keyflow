import AppKit
import Combine
import Foundation
import Yams

struct ProfileRule: Decodable {
    let app: String?
    let title: String?
    let site: String?
    let profile: String

    var summary: String {
        if let site { return "Site · \(site)" }
        if let app { return "App · \(app)" }
        if let title { return "Title · \(title)" }
        return "Focus rule"
    }

    func matchesApp(_ focus: FocusSnapshot) -> Bool {
        if let app {
            let expected = app.lowercased()
            guard expected == focus.appName?.lowercased() ||
                    expected == focus.bundleIdentifier?.lowercased() else { return false }
        }
        if let title {
            guard let windowTitle = focus.windowTitle,
                  windowTitle.range(of: title, options: .caseInsensitive) != nil else { return false }
        }
        if let site {
            guard let activeURL = focus.activeURL,
                  let host = URLComponents(string: activeURL)?.host?.lowercased() else { return false }
            let domain = site.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard host == domain || host.hasSuffix("." + domain) else { return false }
        }
        return app != nil || title != nil || site != nil
    }
}

struct ProfileLayout: Decodable {
    let led: Int?
    let layers: [String: [String: String]]
    let descriptions: [String: String]?
    let icons: [String: SlotIcon]?
}

/// One SF Symbol, or a list drawn side by side (for example `[arrow.up, brain]`).
struct SlotIcon: Decodable {
    let symbols: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let symbol = try? container.decode(String.self) {
            symbols = [symbol]
        } else {
            symbols = try container.decode([String].self)
        }
    }
}

struct CatalogProfile: Identifiable {
    let id: String
    let name: String
    let layoutPath: String
    let layout: ProfileLayout
    let rules: [ProfileRule]

    /// Lists app and window-title rules by type; site rules are not listed.
    var matchSummary: String? {
        guard !rules.isEmpty else { return "Manual selection" }
        let apps = rules.compactMap(\.app).map(Self.appDisplayName)
        let titles = rules.filter { $0.app == nil }.compactMap(\.title)
        var lines: [String] = []
        if !apps.isEmpty { lines.append("Apps: " + apps.joined(separator: ", ")) }
        if !titles.isEmpty { lines.append("Titles: " + titles.joined(separator: ", ")) }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func appDisplayName(_ app: String) -> String {
        guard app.contains("."),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else { return app }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}

struct ProfileCatalog {
    let profiles: [CatalogProfile]
    let rules: [ProfileRule]
    let defaultProfileID: String?
    let settle: TimeInterval
}

struct ProfileCatalogError: LocalizedError {
    let problems: [String]

    var errorDescription: String? {
        "The profile catalog could not be loaded:\n" + problems.map { "• \($0)" }.joined(separator: "\n")
    }
}

private struct CatalogDocument: Decodable {
    let schemaVersion: Int
    let profiles: [ProfileDocument]
    let rules: [ProfileRule]
    let defaultProfile: String?
    let settle: Double?

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case profiles
        case rules
        case defaultProfile = "default"
        case settle
    }
}

private struct ProfileDocument: Decodable {
    let id: String
    let name: String
    let layout: String
}

enum ProfileCatalogLoader {
    static func loadBundled() throws -> ProfileCatalog {
        guard let resources = Bundle.main.resourceURL else {
            throw ProfileCatalogError(problems: ["app resources directory is missing"])
        }
        return try load(catalogURL: resources.appendingPathComponent("Profiles/catalog.yaml"))
    }

    static func load(catalogURL: URL) throws -> ProfileCatalog {
        let catalogURL = catalogURL.standardizedFileURL
        let baseURL = catalogURL.deletingLastPathComponent().resolvingSymlinksInPath()
        let source: String
        do {
            source = try String(contentsOf: catalogURL, encoding: .utf8)
        } catch {
            throw ProfileCatalogError(problems: ["\(catalogURL.path): \(error.localizedDescription)"])
        }

        let rawCatalog: Any
        do {
            guard let value = try Yams.load(yaml: source) else {
                throw ProfileCatalogError(problems: ["\(catalogURL.path): document is empty"])
            }
            rawCatalog = value
        } catch let error as ProfileCatalogError {
            throw error
        } catch {
            throw ProfileCatalogError(problems: ["\(catalogURL.path): invalid YAML: \(error.localizedDescription)"])
        }

        var problems: [String] = []
        guard let root = rawCatalog as? [String: Any] else {
            throw ProfileCatalogError(problems: ["catalog: expected a mapping"])
        }
        checkKeys(root, allowed: ["schemaVersion", "profiles", "rules", "default", "settle"],
                  context: "catalog", problems: &problems)
        if let rawProfiles = root["profiles"] as? [Any] {
            for (index, value) in rawProfiles.enumerated() {
                if let profile = value as? [String: Any] {
                    checkKeys(profile, allowed: ["id", "name", "layout"],
                              context: "profiles[\(index)]", problems: &problems)
                }
            }
        }
        if let rawRules = root["rules"] as? [Any] {
            for (index, value) in rawRules.enumerated() {
                if let rule = value as? [String: Any] {
                    checkKeys(rule, allowed: ["app", "title", "site", "profile"],
                              context: "rules[\(index)]", problems: &problems)
                }
            }
        }

        let document: CatalogDocument
        do {
            document = try YAMLDecoder().decode(CatalogDocument.self, from: source)
        } catch {
            throw ProfileCatalogError(problems: problems + ["\(catalogURL.path): \(error.localizedDescription)"])
        }

        if document.schemaVersion != 1 {
            problems.append("schemaVersion: expected 1, got \(document.schemaVersion)")
        }
        if document.profiles.isEmpty {
            problems.append("profiles: expected at least one profile")
        }

        var profileIDs = Set<String>()
        var loadedLayouts: [String: ProfileLayout] = [:]
        for (index, profile) in document.profiles.enumerated() {
            let location = "profiles[\(index)]"
            let id = profile.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.isEmpty { problems.append("\(location).id: cannot be empty") }
            if !profileIDs.insert(id).inserted { problems.append("\(location).id: duplicate profile id \(id)") }
            if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                problems.append("\(location).name: cannot be empty")
            }
            do {
                loadedLayouts[id] = try loadLayout(profile.layout, relativeTo: baseURL, context: location,
                                                   problems: &problems)
            } catch {
                problems.append("\(location).layout: \(error.localizedDescription)")
            }
        }

        for (index, rule) in document.rules.enumerated() {
            let location = "rules[\(index)]"
            let conditions = [rule.app, rule.title, rule.site].compactMap { $0 }
            if conditions.isEmpty || conditions.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                problems.append("\(location): needs at least one non-empty app, title, or site condition")
            }
            if !profileIDs.contains(rule.profile) {
                problems.append("\(location).profile: unknown profile \(rule.profile)")
            }
        }

        if let defaultProfile = document.defaultProfile, !profileIDs.contains(defaultProfile) {
            problems.append("default: unknown profile \(defaultProfile)")
        }
        let settle = document.settle ?? 0.5
        if !settle.isFinite || settle < 0 || settle > 60 {
            problems.append("settle: expected a number from 0 through 60 seconds")
        }

        if !problems.isEmpty { throw ProfileCatalogError(problems: problems) }

        let rulesByProfile = Dictionary(grouping: document.rules, by: \.profile)
        let profiles = document.profiles.map { profile in
            CatalogProfile(id: profile.id, name: profile.name, layoutPath: profile.layout,
                           layout: loadedLayouts[profile.id]!, rules: rulesByProfile[profile.id] ?? [])
        }
        return ProfileCatalog(profiles: profiles, rules: document.rules,
                              defaultProfileID: document.defaultProfile, settle: settle)
    }

    private static func loadLayout(_ relativePath: String, relativeTo baseURL: URL,
                                   context: String, problems: inout [String]) throws -> ProfileLayout {
        guard !relativePath.hasPrefix("/") else {
            throw ProfileCatalogError(problems: ["layout path must be relative to the profile catalog"])
        }
        let layoutURL = baseURL.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        let basePath = baseURL.resolvingSymlinksInPath().path + "/"
        guard layoutURL.path.hasPrefix(basePath) else {
            throw ProfileCatalogError(problems: ["layout path escapes the profile resources directory"])
        }

        let source = try String(contentsOf: layoutURL, encoding: .utf8)
        let raw: Any
        do {
            guard let value = try Yams.load(yaml: source) else {
                throw ProfileCatalogError(problems: ["layout document is empty"])
            }
            raw = value
        } catch let error as ProfileCatalogError {
            throw error
        } catch {
            throw ProfileCatalogError(problems: ["invalid YAML: \(error.localizedDescription)"])
        }

        guard let root = raw as? [String: Any] else {
            throw ProfileCatalogError(problems: ["expected a mapping with led/layers"])
        }
        checkKeys(root, allowed: ["led", "layers", "descriptions", "icons"], context: "\(context).layout",
                  problems: &problems)
        guard let rawLayers = root["layers"] as? [String: Any] else {
            problems.append("\(context).layout.layers: expected a mapping")
            throw ProfileCatalogError(problems: ["invalid layers mapping"])
        }
        let supportedSlots: Set<String> = ["key1", "key2", "key3", "key4", "key5", "key6",
                                           "knob-left", "knob-press", "knob-right"]
        for (layer, value) in rawLayers {
            if layer != "1" {
                problems.append("\(context).layout.layers.\(layer): this pad supports profile mappings on layer 1 only")
            }
            guard let slots = value as? [String: Any] else {
                problems.append("\(context).layout.layers.\(layer): expected a slot mapping")
                continue
            }
            checkKeys(slots, allowed: supportedSlots, context: "\(context).layout.layers.\(layer)",
                      problems: &problems)
            for (slot, value) in slots {
                guard let action = value as? String else {
                    problems.append("\(context).layout.layers.\(layer).\(slot): action must be a string")
                    continue
                }
                if let issue = ActionSyntax.validate(action) {
                    problems.append("\(context).layout.layers.\(layer).\(slot): \(issue)")
                }
            }
        }
        if let rawDescriptions = root["descriptions"] {
            if let descriptions = rawDescriptions as? [String: Any] {
                checkKeys(descriptions, allowed: supportedSlots, context: "\(context).layout.descriptions",
                          problems: &problems)
                for (slot, value) in descriptions where !(value is String) {
                    problems.append("\(context).layout.descriptions.\(slot): description must be a string")
                }
            } else {
                problems.append("\(context).layout.descriptions: expected a slot mapping")
            }
        }
        if let rawIcons = root["icons"] {
            if let icons = rawIcons as? [String: Any] {
                checkKeys(icons, allowed: supportedSlots, context: "\(context).layout.icons", problems: &problems)
                for (slot, value) in icons {
                    guard let symbols = value as? [String] ?? (value as? String).map({ [$0] }),
                          !symbols.isEmpty else {
                        problems.append("\(context).layout.icons.\(slot): icon must be an SF Symbol name or a list of them")
                        continue
                    }
                    for symbol in symbols where NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil {
                        problems.append("\(context).layout.icons.\(slot): unknown SF Symbol \(symbol)")
                    }
                }
            } else {
                problems.append("\(context).layout.icons: expected a slot mapping")
            }
        }
        if let rawLED = root["led"], let led = rawLED as? Int, !(0...2).contains(led) {
            problems.append("\(context).layout.led: expected 0, 1, or 2")
        }

        do {
            return try YAMLDecoder().decode(ProfileLayout.self, from: source)
        } catch {
            throw ProfileCatalogError(problems: ["cannot decode layout: \(error.localizedDescription)"])
        }
    }

    private static func checkKeys(_ mapping: [String: Any], allowed: Set<String>, context: String,
                                  problems: inout [String]) {
        for unknown in mapping.keys.sorted() where !allowed.contains(unknown) {
            problems.append("\(context).\(unknown): unknown field")
        }
    }
}

final class ProfileCatalogStore: ObservableObject {
    @Published private(set) var profiles: [CatalogProfile] = []
    @Published private(set) var selectedProfileID: String?
    @Published private(set) var selectionOrigin: ProfileSelectionOrigin?
    @Published private(set) var errorMessage: String?
    private(set) var rules: [ProfileRule] = []
    private(set) var defaultProfileID: String?
    private(set) var settle: TimeInterval = 0.5

    init() { reload() }

    func select(_ profile: CatalogProfile) {
        selectedProfileID = profile.id
        selectionOrigin = .manual
    }

    @discardableResult
    func selectAutomatically(profileID: String) -> Bool {
        guard profiles.contains(where: { $0.id == profileID }) else { return false }
        selectedProfileID = profileID
        selectionOrigin = .automatic
        return true
    }

    var selectedProfileName: String? {
        profiles.first(where: { $0.id == selectedProfileID })?.name
    }

    func profileName(id: String) -> String? {
        profiles.first(where: { $0.id == id })?.name
    }

    func reload() {
        do {
            let catalog = try ProfileCatalogLoader.loadBundled()
            profiles = catalog.profiles
            rules = catalog.rules
            defaultProfileID = catalog.defaultProfileID
            settle = catalog.settle
            selectedProfileID = catalog.defaultProfileID
            selectionOrigin = catalog.defaultProfileID == nil ? nil : .automatic
            errorMessage = nil
        } catch {
            profiles = []
            rules = []
            defaultProfileID = nil
            selectedProfileID = nil
            selectionOrigin = nil
            errorMessage = error.localizedDescription
        }
    }
}

enum ProfileSelectionOrigin: Equatable {
    case automatic
    case manual
}

private enum ActionSyntax {
    private static let modifiers: Set<String> = ["ctrl", "opt", "shift", "cmd", "rctrl", "ropt", "rshift", "rcmd"]
    private static let modifierAliases: [String: String] = [
        "control": "ctrl", "option": "opt", "alt": "opt", "command": "cmd", "win": "cmd",
        "super": "cmd", "meta": "cmd", "gui": "cmd", "rcontrol": "rctrl", "roption": "ropt",
        "ralt": "ropt", "rcommand": "rcmd", "rwin": "rcmd",
    ]
    private static let keyAliases: [String: String] = [
        "return": "enter", "escape": "esc", "spacebar": "space", "-": "minus", "=": "equal",
        "[": "lbracket", "]": "rbracket", "\\": "backslash", ";": "semicolon", "'": "quote",
        "`": "grave", "backtick": "grave", ".": "period", "dot": "period", "/": "slash",
        "pgup": "pageup", "pgdn": "pagedown", "ins": "insert", "prtsc": "printscreen",
        "arrow-left": "left", "arrow-right": "right", "arrow-up": "up", "arrow-down": "down",
    ]
    private static let mediaAliases: [String: String] = [
        "play-pause": "play", "previous": "prev", "vol-up": "volume-up", "vol-down": "volume-down",
        "dictate": "dictation",
    ]
    private static let mouseAliases: [String: String] = [
        "left-click": "click", "wheel-up": "scroll-up", "wheel-down": "scroll-down",
    ]
    private static let keys: Set<String> = Set(
        Array("abcdefghijklmnopqrstuvwxyz0123456789").map(String.init) + [
            "enter", "esc", "backspace", "tab", "space", "minus", "equal", "lbracket", "rbracket",
            "backslash", "semicolon", "quote", "grave", "comma", "period", "slash", "capslock",
            "printscreen", "scrolllock", "pause", "insert", "home", "pageup", "forward-delete", "end",
            "pagedown", "right", "left", "down", "up", "numlock", "kp-slash", "kp-asterisk", "kp-minus",
            "kp-plus", "kp-enter", "kp-0", "kp-period", "menu", "kp-equal",
        ] + (1...24).map { "f\($0)" } + (1...9).map { "kp-\($0)" }
    )
    private static let media: Set<String> = ["play", "next", "prev", "stop", "mute", "volume-up", "volume-down",
                                             "brightness-up", "brightness-down", "dictation"]
    private static let mouse: Set<String> = ["click", "right-click", "middle-click", "scroll-up", "scroll-down"]

    static func validate(_ text: String) -> String? {
        let steps = text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !steps.isEmpty, steps.allSatisfy({ !$0.isEmpty }) else { return "action or sequence step is empty" }
        guard steps.count <= 5 else { return "sequence exceeds the device limit of 5 steps" }

        for step in steps {
            let tokens = step.split(separator: "+", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            guard !tokens.isEmpty, tokens.allSatisfy({ !$0.isEmpty }) else { return "empty key name in action" }

            let resolvedModifiers = tokens.map { modifierAliases[$0] ?? $0 }.filter { modifiers.contains($0) }
            let others = tokens.filter { !modifiers.contains(modifierAliases[$0] ?? $0) }
            guard others.count <= 1 else { return "only one regular key is allowed per step" }
            guard let token = others.first else { continue }

            let mediaName = mediaAliases[token] ?? token
            if media.contains(mediaName) {
                if !resolvedModifiers.isEmpty { return "media actions cannot have modifiers" }
                if steps.count > 1 { return "media actions cannot be in a sequence" }
                continue
            }
            let mouseName = mouseAliases[token] ?? token
            if mouse.contains(mouseName) {
                if steps.count > 1 { return "mouse actions cannot be in a sequence" }
                continue
            }
            if token == "delete" || token == "del" {
                return "\(token) is ambiguous on macOS; use backspace or forward-delete"
            }
            let keyName = keyAliases[token] ?? token
            if !keys.contains(keyName) { return "unknown key/action \(token)" }
        }
        return nil
    }
}
