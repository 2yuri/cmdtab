import AppKit
import SwiftUI

extension Color {
    static let volt = Color("Volt")
    static let ink = Color("Ink")

    /// Text on the accent colour: white on the light-mode green, ink on the dark-mode volt.
    static let onAccent = Color(nsColor: NSColor(name: "onAccent") { appearance in
        appearance.isDark ? NSColor(named: "Ink") ?? .black : .white
    })
}

/// The filled accent button from the design (the system prompt style can't use ink text on volt).
struct ProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.onAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// A key as drawn on a keyboard shortcut: ⌘, ⇥, esc…
struct KeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(minWidth: 10)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.separator))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}

/// A small status capsule: "Allowed", "Never requested"…
struct StatusPill: View {
    let title: String
    let isPositive: Bool

    var body: some View {
        let tint = isPositive ? Color.accentColor : Color.secondary
        Label(title, systemImage: isPositive ? "checkmark" : "minus")
            .labelStyle(PillLabelStyle())
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
    }

    private struct PillLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 4) {
                configuration.icon.imageScale(.small)
                configuration.title
            }
        }
    }
}
