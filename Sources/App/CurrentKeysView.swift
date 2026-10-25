import SwiftUI

/// Shows the selected profile's mappings laid out like the pad: key1–key3 on top, key4–key6
/// below, and the knob as a turn-left / press / turn-right strip.
struct CurrentKeysView: View {
    let profileID: String?
    let mappings: [String: String]
    let descriptions: [String: String]
    let icons: [String: String]

    @State private var hoveredSlot: String?
    @State private var highlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("CURRENT KEYS")
                .font(.system(size: 9, weight: .semibold)).tracking(0.7)
                .foregroundStyle(.secondary)
                .padding(.bottom, 3)
            ForEach([1, 4], id: \.self) { first in
                HStack(spacing: 5) {
                    ForEach(first..<first + 3, id: \.self) { key($0) }
                }
            }
            HStack(spacing: 5) {
                knobTurn("knob-left", symbol: "arrow.counterclockwise", leading: true)
                knobPress
                knobTurn("knob-right", symbol: "arrow.clockwise", leading: false)
            }
            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 3)
        }
        .padding(.horizontal, 16).padding(.top, 9).padding(.bottom, 10)
        .onChange(of: profileID) { _ in
            highlighted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.15)) { highlighted = false }
            }
        }
    }

    private func key(_ number: Int) -> some View {
        let slot = "key\(number)"
        return KeyGlyph(action: mappings[slot], icon: icons[slot])
            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
            .overlay(alignment: .topLeading) {
                Text("\(number)").font(.system(size: 8)).foregroundStyle(.secondary)
                    .padding(.top, 4).padding(.leading, 6)
            }
            .background(keyShape(RoundedRectangle(cornerRadius: 7, style: .continuous)))
            .modifier(SlotHover(slot: slot, hoveredSlot: $hoveredSlot))
    }

    private func knobTurn(_ slot: String, symbol: String, leading: Bool) -> some View {
        HStack(spacing: 6) {
            if leading { turnIcon(symbol) }
            KeyGlyph(action: mappings[slot], icon: icons[slot])
            if !leading { turnIcon(symbol) }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: leading ? .leading : .trailing)
        .background(keyShape(Capsule(style: .continuous)))
        .modifier(SlotHover(slot: slot, hoveredSlot: $hoveredSlot))
    }

    private var knobPress: some View {
        KeyGlyph(action: mappings["knob-press"], icon: icons["knob-press"])
            .frame(width: 40, height: 40)
            .background(keyShape(Circle()))
            .modifier(SlotHover(slot: "knob-press", hoveredSlot: $hoveredSlot))
    }

    private func turnIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func keyShape<S: Shape>(_ shape: S) -> some View {
        shape.fill(highlighted ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.07))
            .overlay(shape.stroke(highlighted ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1))
    }

    private var hint: String {
        guard let hoveredSlot else { return "Hover a key or the knob to see its action." }
        let action = mappings[hoveredSlot].flatMap { $0.isEmpty ? nil : $0 }
        let detail = action == nil ? "not mapped" : descriptions[hoveredSlot] ?? action!
        return "\(Self.slotNames[hoveredSlot] ?? hoveredSlot) · \(detail)"
    }

    private static let slotNames = [
        "key1": "Key 1", "key2": "Key 2", "key3": "Key 3", "key4": "Key 4", "key5": "Key 5",
        "key6": "Key 6", "knob-left": "Knob · turn left", "knob-press": "Knob · press",
        "knob-right": "Knob · turn right",
    ]
}

private struct SlotHover: ViewModifier {
    let slot: String
    @Binding var hoveredSlot: String?

    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside {
                hoveredSlot = slot
            } else if hoveredSlot == slot {
                hoveredSlot = nil
            }
        }
    }
}

/// Renders a layout's icon override, or the action with icons or Mac key symbols where one
/// exists; steps of a sequence are separated by a dim "›" so they don't read as arrow keys.
private struct KeyGlyph: View {
    let action: String?
    let icon: String?

    var body: some View {
        let steps = Self.steps(action)
        HStack(spacing: 2) {
            if let icon, !steps.isEmpty {
                Image(systemName: icon).font(.system(size: 13, weight: .medium))
            } else if steps.isEmpty {
                Text("—").foregroundStyle(.tertiary)
            } else {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, tokens in
                    if index > 0 {
                        Text("›").font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 1)
                    }
                    HStack(spacing: 0) {
                        ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                            if let symbol = Self.icons[token] {
                                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                            } else {
                                Text(Self.modifiers[token] ?? Self.symbols[token] ?? token.uppercased())
                            }
                        }
                    }
                }
            }
        }
        .font(.system(size: 13, weight: .medium))
        .lineLimit(1)
    }

    private static func steps(_ action: String?) -> [[String]] {
        guard let action = action?.trimmingCharacters(in: .whitespaces).lowercased(), !action.isEmpty else {
            return []
        }
        return action.split(separator: ",").map { step in
            step.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    private static let icons = [
        "dictation": "mic", "dictate": "mic", "mute": "speaker.slash",
        "volume-up": "speaker.wave.3", "vol-up": "speaker.wave.3",
        "volume-down": "speaker.wave.1", "vol-down": "speaker.wave.1",
        "play": "playpause", "play-pause": "playpause", "next": "forward.end", "prev": "backward.end",
        "previous": "backward.end", "pageup": "chevron.up.2", "pgup": "chevron.up.2",
        "pagedown": "chevron.down.2", "pgdn": "chevron.down.2", "click": "computermouse",
        "left-click": "computermouse",
    ]

    private static let modifiers = [
        "cmd": "⌘", "command": "⌘", "rcmd": "⌘", "opt": "⌥", "option": "⌥", "alt": "⌥", "ropt": "⌥",
        "shift": "⇧", "rshift": "⇧", "ctrl": "⌃", "control": "⌃", "rctrl": "⌃",
    ]

    private static let symbols = [
        "esc": "esc", "escape": "esc", "enter": "↩", "return": "↩", "tab": "⇥", "space": "␣",
        "backspace": "⌫", "forward-delete": "⌦", "up": "↑", "down": "↓", "left": "←", "right": "→",
        "arrow-up": "↑", "arrow-down": "↓", "arrow-left": "←", "arrow-right": "→",
        "home": "↖", "end": "↘", "scroll-up": "⇡", "scroll-down": "⇣",
    ]
}
