import Foundation

enum ProfilePacketEncoder {
    static let slots = ["key1", "key2", "key3", "key4", "key5", "key6",
                        "knob-left", "knob-press", "knob-right"]

    static func packets(for layout: ProfileLayout, full: Bool,
                        comparedTo previous: [String: String]?, previousLED: Int?) throws -> [[UInt8]] {
        var packets: [[UInt8]] = []
        let mappings = layout.layers["1"] ?? [:]
        for slot in slots {
            let action = mappings[slot] ?? ""
            if full || previous?[slot] != action {
                packets += try bindingPackets(slot: slot, action: action)
            }
        }
        if let led = layout.led, full || previousLED != led {
            packets += ledPackets(mode: led)
        }
        return packets
    }

    static func canonicalState(for layout: ProfileLayout) -> [String: String] {
        Dictionary(uniqueKeysWithValues: slots.map { ($0, (layout.layers["1"] ?? [:])[$0] ?? "") })
    }

    private static func bindingPackets(slot: String, action: String) throws -> [[UInt8]] {
        guard let slotID = slotIDs[slot] else { throw EncodingError.invalidAction("Unknown slot \(slot)") }
        let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let steps = normalized.isEmpty ? [] : normalized.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var parsed: [(UInt8, UInt8)] = []
        var media: UInt16?
        var mouse: (UInt8, UInt8, UInt8)?
        for step in steps {
            var mods: UInt8 = 0
            for tokenRaw in step.split(separator: "+", omittingEmptySubsequences: false) {
                let token = String(tokenRaw).trimmingCharacters(in: .whitespacesAndNewlines)
                if let bit = modifierBits[modifierAliases[token] ?? token] { mods |= bit; continue }
                let canonical = keyAliases[token] ?? token
                if let code = keyCodes[canonical] {
                    parsed.append((mods, code))
                } else if let usage = mediaCodes[mediaAliases[token] ?? token] {
                    media = usage
                } else if let mouseValue = mouseValues[mouseAliases[token] ?? token] {
                    mouse = (mouseValue.0, 0, mods)
                } else {
                    throw EncodingError.invalidAction("Unsupported action token \(token)")
                }
            }
        }

        var body: [[UInt8]] = []
        if let media {
            body = [packet([slotID, 0x12, UInt8(media & 0xff), UInt8(media >> 8)])]
        } else if let mouse {
            body = [packet([slotID, 0x13, mouse.0, 0, 0, mouse.1, mouse.2])]
        } else {
            if parsed.isEmpty { parsed = [(0, 0)] }
            guard parsed.count <= 5 else { throw EncodingError.invalidAction("Too many sequence steps") }
            body.append(packet([slotID, 0x11, UInt8(parsed.count), 0, parsed[0].0, 0]))
            for (index, step) in parsed.enumerated() {
                body.append(packet([slotID, 0x11, UInt8(parsed.count), UInt8(index + 1), step.0, step.1]))
            }
        }
        return [packet([0xa1, 1])] + body + [packet([0xaa, 0xaa])]
    }

    private static func ledPackets(mode: Int) -> [[UInt8]] {
        [packet([0xa1, 1]), packet([0xb0, 0x18, UInt8(mode)]), packet([0xaa, 0xa1])]
    }

    private static func packet(_ payload: [UInt8]) -> [UInt8] {
        ([0x03] + payload).padding(to: 64, with: 0)
    }

    private static let slotIDs: [String: UInt8] = ["key1": 1, "key2": 2, "key3": 3,
        "key4": 4, "key5": 5, "key6": 6, "knob-left": 13, "knob-press": 14, "knob-right": 15]
    private static let modifierBits: [String: UInt8] = ["ctrl": 0x01, "shift": 0x02, "opt": 0x04,
        "cmd": 0x08, "rctrl": 0x10, "rshift": 0x20, "ropt": 0x40, "rcmd": 0x80]
    private static let modifierAliases = ["control": "ctrl", "option": "opt", "alt": "opt",
        "command": "cmd", "win": "cmd", "super": "cmd", "meta": "cmd", "gui": "cmd",
        "rcontrol": "rctrl", "roption": "ropt", "ralt": "ropt", "rcommand": "rcmd", "rwin": "rcmd"]
    private static let keyCodes: [String: UInt8] = {
        var map: [String: UInt8] = [:]
        for value in 0..<26 { map[String(UnicodeScalar(97 + value)!)] = UInt8(0x04 + value) }
        for n in 1...9 { map[String(n)] = UInt8(0x1d + n) }
        map["0"] = 0x27
        let fixed: [String: UInt8] = ["enter":0x28,"esc":0x29,"backspace":0x2a,"tab":0x2b,
            "space":0x2c,"minus":0x2d,"equal":0x2e,"lbracket":0x2f,"rbracket":0x30,
            "backslash":0x31,"semicolon":0x33,"quote":0x34,"grave":0x35,"comma":0x36,
            "period":0x37,"slash":0x38,"capslock":0x39,"printscreen":0x46,"scrolllock":0x47,
            "pause":0x48,"insert":0x49,"home":0x4a,"pageup":0x4b,"forward-delete":0x4c,
            "end":0x4d,"pagedown":0x4e,"right":0x4f,"left":0x50,"down":0x51,"up":0x52,
            "numlock":0x53,"kp-slash":0x54,"kp-asterisk":0x55,"kp-minus":0x56,"kp-plus":0x57,
            "kp-enter":0x58,"kp-0":0x62,"kp-period":0x63,"menu":0x65,"kp-equal":0x67]
        map.merge(fixed) { _, new in new }
        for n in 1...12 { map["f\(n)"] = UInt8(0x39 + n) }
        for n in 13...24 { map["f\(n)"] = UInt8(0x68 + n - 13) }
        for n in 1...9 { map["kp-\(n)"] = UInt8(0x58 + n) }
        return map
    }()
    private static let keyAliases = ["return":"enter", "escape":"esc", "spacebar":"space", "-":"minus",
        "=":"equal", "[":"lbracket", "]":"rbracket", "\\":"backslash", ";":"semicolon",
        "'":"quote", "`":"grave", "backtick":"grave", ".":"period", "dot":"period", "/":"slash",
        "pgup":"pageup", "pgdn":"pagedown", "ins":"insert", "prtsc":"printscreen",
        "arrow-left":"left", "arrow-right":"right", "arrow-up":"up", "arrow-down":"down"]
    private static let mediaCodes: [String: UInt16] = ["play":0xcd,"next":0xb5,"prev":0xb6,"stop":0xb7,
        "mute":0xe2,"volume-up":0xe9,"volume-down":0xea,"brightness-up":0x6f,
        "brightness-down":0x70,"dictation":0xcf]
    private static let mediaAliases = ["play-pause":"play", "previous":"prev", "vol-up":"volume-up",
        "vol-down":"volume-down", "dictate":"dictation"]
    private static let mouseValues: [String: (UInt8, UInt8)] = ["click":(1,0),"right-click":(2,0),
        "middle-click":(4,0),"scroll-up":(0,1),"scroll-down":(0,0xff)]
    private static let mouseAliases = ["left-click":"click", "wheel-up":"scroll-up", "wheel-down":"scroll-down"]

    private enum EncodingError: LocalizedError {
        case invalidAction(String)
        var errorDescription: String? {
            switch self {
            case .invalidAction(let reason): reason
            }
        }
    }
}

private extension Array where Element == UInt8 {
    func padding(to count: Int, with byte: UInt8) -> [UInt8] {
        if self.count >= count { return self }
        return self + Array(repeating: byte, count: count - self.count)
    }
}
