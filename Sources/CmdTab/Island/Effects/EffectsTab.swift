import AppKit
import SwiftUI

/// The open Effects tab: a live preview over the effect picker, where it falls, how it falls, and
/// whether it rests on battery. With Off, everything below the picker stays in place, dimmed.
struct EffectsTab: View {
    @Bindable var preferences: Preferences
    let weather: WeatherService
    let effects: IslandEffects

    private var isOff: Bool { preferences.islandEffect == .off }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TabHeader(title: "Effects") {
                if preferences.islandEffect == .weather { SkyNow(preferences: preferences, weather: weather) }
            }
            EffectStage(preferences: preferences, kind: previewKind, style: effects.style)
            Group {
                HStack {
                    Text("Show on").font(.system(size: 13, weight: .medium)).foregroundStyle(IslandStyle.primary)
                    Spacer()
                    ShowOnSegments(selection: $preferences.islandEffectPlacement)
                }
                VStack(spacing: 10) {
                    IslandSlider(label: "Amount", low: "drop", high: "humidity", value: $preferences.islandEffectAmount)
                    IslandSlider(label: "Size", low: "circle", high: "circle", lowSize: 6, value: $preferences.islandEffectSize)
                    IslandSlider(label: "Speed", low: "tortoise", high: "hare", value: $preferences.islandEffectSpeed)
                    IslandSlider(label: "Opacity", low: "circle.dashed", high: "circle", value: $preferences.islandEffectOpacity)
                    // The same height whatever is picked: fireflies swap the direction for a colour.
                    if preferences.islandEffect == .fireflies {
                        FireflyColors(color: $preferences.islandEffectFireflyColor)
                    } else {
                        IslandSlider(
                            label: "Direction", low: "arrow.down.left", high: "arrow.down.right",
                            value: Binding(
                                get: { (preferences.islandEffectAngle + Self.maxAngle) / (2 * Self.maxAngle) },
                                set: { preferences.islandEffectAngle = (($0 * 2 - 1) * Self.maxAngle / 5).rounded() * 5 }
                            ),
                            centred: true
                        )
                    }
                }
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                HStack(spacing: 8) {
                    Image(systemName: "battery.50").font(.system(size: 13)).foregroundStyle(IslandStyle.secondary)
                    Text("Pause on battery").font(.system(size: 13, weight: .medium)).foregroundStyle(IslandStyle.primary)
                    Spacer()
                    IslandSwitch(isOn: $preferences.islandEffectPausesOnBattery)
                }
            }
            .disabled(isOff)
            .opacity(isOff ? 0.4 : 1)
        }
        .onAppear {
            if preferences.islandEffect == .weather { weather.refreshIfNeeded(place: preferences.islandWeatherPlace) }
        }
    }

    /// The slant either way, in degrees.
    static let maxAngle = 50.0

    /// What the preview shows: the pick, or for Weather what the sky brings now.
    private var previewKind: EffectKind? {
        switch preferences.islandEffect {
        case .off: nil
        case .rain: .rain
        case .snow: .snow
        case .fireflies: .fireflies
        case .weather: weather.report.flatMap { IslandEffects.kind(code: $0.code, isDay: $0.isDay) }
        }
    }
}

/// "Drizzle in Cascavel", with the sky's symbol.
private struct SkyNow: View {
    let preferences: Preferences
    let weather: WeatherService

    var body: some View {
        HStack(spacing: 6) {
            if let report = weather.report {
                Image(systemName: WeatherService.symbol(report.code, isDay: report.isDay)).font(.system(size: 11))
            }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 12))
        .foregroundStyle(IslandStyle.secondary)
    }

    private var text: String {
        guard let place = preferences.islandWeatherPlace else { return "Pick a city in Weather" }
        guard let report = weather.report else { return place.name }
        return "\(WeatherService.words(report.code)) in \(place.name)"
    }
}

/// The live preview, a little screen with the island and a window, over the effect picker.
private struct EffectStage: View {
    @Bindable var preferences: Preferences
    let kind: EffectKind?
    let style: EffectStyle

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                Color(red: 0.078, green: 0.086, blue: 0.102)
                UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6, style: .continuous)
                    .fill(Color(red: 0.141, green: 0.149, blue: 0.169))
                    .frame(width: 150, height: 20)
                    .offset(x: 40, y: 50)
                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.12)).frame(width: 18, height: 4).offset(x: 50, y: 55)
                UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9, style: .continuous)
                    .fill(.black)
                    .frame(width: 120, height: 18)
                    .frame(maxWidth: .infinity)
                IslandEffectView(kind: kind, style: style).allowsHitTesting(false)
            }
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack(spacing: 2) {
                ForEach(IslandEffect.allCases, id: \.self) { effect in
                    EffectOption(effect: effect, isOn: preferences.islandEffect == effect) {
                        preferences.islandEffect = effect
                    }
                }
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct EffectOption: View {
    let effect: IslandEffect
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isOn ? IslandStyle.volt : IslandStyle.secondary)
                    .frame(height: 16)
                Text(effect.label)
                    .font(.system(size: 11, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(isOn ? IslandStyle.volt : IslandStyle.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 7)
            .background(isOn ? IslandStyle.volt.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var symbol: String {
        switch effect {
        case .weather: "cloud.sun.rain"
        case .rain: "cloud.rain"
        case .snow: "snowflake"
        case .fireflies: "sparkles"
        case .off: "circle.slash"
        }
    }
}

private struct ShowOnSegments: View {
    @Binding var selection: EffectPlacement

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EffectPlacement.allCases, id: \.self) { placement in
                let isOn = selection == placement
                Button { selection = placement } label: {
                    Text(placement.label)
                        .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                        .foregroundStyle(isOn ? IslandStyle.primary : IslandStyle.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(isOn ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .frame(width: 220)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Label, an icon at each end and a Volt track. Centred ones fill from the middle, with a tick there.
private struct IslandSlider: View {
    let label: String
    let low: String
    let high: String
    var lowSize: CGFloat = 11
    @Binding var value: Double
    var centred = false

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(IslandStyle.primary)
                .frame(width: 64, alignment: .leading)
            Image(systemName: low).font(.system(size: lowSize)).foregroundStyle(IslandStyle.tertiary).frame(width: 13)
            GeometryReader { proxy in
                let width = proxy.size.width
                let knob = min(max(value, 0), 1) * width
                let start = centred ? min(knob, width / 2) : 0
                let end = centred ? max(knob, width / 2) : knob
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15)).frame(height: 4)
                    if centred {
                        RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.25)).frame(width: 2, height: 10).offset(x: width / 2 - 1)
                    }
                    Capsule().fill(IslandStyle.volt).frame(width: max(end - start, 0), height: 4).offset(x: start)
                    Circle()
                        .fill(IslandStyle.primary)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
                        .offset(x: knob - 7)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    value = min(max(drag.location.x / max(width, 1), 0), 1)
                })
            }
            .frame(height: 20)
            Image(systemName: high).font(.system(size: 11)).foregroundStyle(IslandStyle.tertiary).frame(width: 13)
        }
        .frame(height: 20)
    }
}

/// The fireflies' colour: five to pick from, or any hue. The rainbow turns the row into a hue
/// track right here in the island; the check goes back to the swatches.
private struct FireflyColors: View {
    @Binding var color: String
    @State private var picking = false

    private var isCustom: Bool { !EffectStyle.fireflyColors.contains(color) }

    var body: some View {
        HStack(spacing: 10) {
            Text("Color")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(IslandStyle.primary)
                .frame(width: 64, alignment: .leading)
            if picking {
                HueTrack(color: $color)
                Button { picking = false } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(IslandStyle.primary)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.12), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    ForEach(EffectStyle.fireflyColors, id: \.self) { hex in
                        Button { color = hex } label: {
                            Swatch(isOn: color == hex) { Circle().fill(Self.swiftUI(hex)) }
                        }
                        .buttonStyle(.plain)
                    }
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 14)
                    Button {
                        if !isCustom { color = HueTrack.hex(hue: 0.53) }
                        picking = true
                    } label: {
                        Swatch(isOn: isCustom) {
                            if isCustom {
                                Circle().fill(Self.swiftUI(color))
                            } else {
                                ZStack {
                                    Circle().fill(AngularGradient(colors: HueTrack.colors, center: .center))
                                    Image(systemName: "plus").font(.system(size: 7, weight: .bold)).foregroundStyle(IslandStyle.primary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 20)
    }

    static func swiftUI(_ hex: String) -> Color {
        let rgb = EffectStyle.components(hex) ?? (1, 1, 1)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private struct Swatch<Fill: View>: View {
        let isOn: Bool
        @ViewBuilder var fill: Fill

        var body: some View {
            fill
                .frame(width: 16, height: 16)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(isOn ? IslandStyle.primary : .clear, lineWidth: 1.5))
                .contentShape(Circle())
        }
    }
}

/// A rainbow to drag along; the knob wears the colour picked.
private struct HueTrack: View {
    @Binding var color: String

    static let colors: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { hue in
        Color(hue: hue, saturation: saturation, brightness: 1)
    }
    /// Soft enough to glow, not neon.
    static let saturation = 0.65

    static func hex(hue: Double) -> String {
        let color = NSColor(hue: hue, saturation: saturation, brightness: 1, alpha: 1).usingColorSpace(.sRGB) ?? .white
        return EffectStyle.hex(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
    }

    private var hue: Double {
        guard let rgb = EffectStyle.components(color) else { return 0 }
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1).hueComponent
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: Self.colors, startPoint: .leading, endPoint: .trailing)).frame(height: 8)
                Circle()
                    .fill(FireflyColors.swiftUI(color))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(IslandStyle.primary, lineWidth: 2))
                    .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
                    .offset(x: hue * width - 8)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                color = Self.hex(hue: min(max(drag.location.x / max(width, 1), 0), 0.999))
            })
        }
        .frame(height: 20)
    }
}

/// Volt when on, with a dark knob; grey when off.
private struct IslandSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Capsule()
                .fill(isOn ? IslandStyle.volt : Color.white.opacity(0.18))
                .frame(width: 32, height: 18)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(isOn ? Color(red: 0.043, green: 0.043, blue: 0.047) : IslandStyle.primary)
                        .frame(width: 14, height: 14)
                        .padding(2)
                }
                .animation(.spring(duration: 0.2, bounce: 0), value: isOn)
        }
        .buttonStyle(.plain)
    }
}
