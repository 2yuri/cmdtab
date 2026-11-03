import AVKit
import QuartzCore
import SwiftUI

/// The open Music tab: artwork, track, progress, controls. With nothing playing it keeps the same
/// shape, quiet: a blank cover, "Nothing playing", the controls dimmed.
struct MusicTab: View {
    let music: NowPlayingMonitor

    var body: some View {
        let track = music.track
        VStack(spacing: 14) {
            TrackHeader(music: music, artworkSize: 72, titleSize: 16)
            Progress(track: track ?? NowPlaying(title: "", rate: 0, isPlaying: false)) { music.seek(to: $0) }
                .opacity(track == nil ? 0.3 : 1)
                .disabled(track == nil)
            HStack {
                ControlButton(symbol: "shuffle", size: 15) { music.send(.shuffle) }
                Spacer()
                ControlButton(symbol: "backward.fill", size: 18) { music.send(.previous) }
                Spacer()
                Button { music.send(.toggle) } label: {
                    Image(systemName: track?.isPlaying == true ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(IslandStyle.primary, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                ControlButton(symbol: "forward.fill", size: 18) { music.send(.next) }
                Spacer()
                RoutePicker().frame(width: 30, height: 30)
            }
            .padding(.horizontal, 4)
            .opacity(track == nil ? 0.3 : 1)
            .disabled(track == nil)
        }
    }
}

/// Artwork, title, artist and app: the Music tab and the Overview share it, and with nothing
/// playing both show a blank cover with "Nothing playing".
struct TrackHeader: View {
    let music: NowPlayingMonitor
    let artworkSize: CGFloat
    let titleSize: CGFloat

    var body: some View {
        HStack(spacing: artworkSize > 66 ? 14 : 12) {
            if let track = music.track {
                Artwork(image: music.artwork ?? music.app?.icon, size: artworkSize)
                    .onTapGesture { music.openApp() }
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.hasDetails ? track.title : "Playing in \(music.app?.localizedName ?? "an app")")
                        .font(.system(size: titleSize, weight: .bold))
                        .foregroundStyle(IslandStyle.primary)
                        .lineLimit(1)
                    if let artist = track.artist {
                        Text(artist).font(.system(size: titleSize - 3)).foregroundStyle(IslandStyle.secondary).lineLimit(1)
                    }
                    if let app = music.app, let name = app.localizedName {
                        Button { music.openApp() } label: {
                            HStack(spacing: 4) {
                                if let icon = app.icon {
                                    Image(nsImage: icon).resizable().frame(width: 12, height: 12)
                                }
                                Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            }
                            .foregroundStyle(IslandStyle.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                ArtworkPlaceholder(size: artworkSize)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing playing")
                        .font(.system(size: titleSize, weight: .bold))
                        .foregroundStyle(IslandStyle.secondary)
                        .lineLimit(1)
                    Text("Play something in any app")
                        .font(.system(size: titleSize - 3))
                        .foregroundStyle(IslandStyle.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A blank cover with a note, for when nothing plays.
struct ArtworkPlaceholder: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: size * 0.19, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .overlay(Image(systemName: "music.note").font(.system(size: size * 0.36, weight: .medium)).foregroundStyle(IslandStyle.tertiary))
            .frame(width: size, height: size)
    }
}

private struct Progress: View {
    let track: NowPlaying
    let seek: (TimeInterval) -> Void

    var body: some View {
        // Ticks once a second, only while the tab is open.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let position = track.position(at: context.date) ?? 0
            let duration = track.duration ?? 0
            VStack(spacing: 6) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule()
                            .fill(IslandStyle.primary)
                            .frame(width: duration > 0 ? proxy.size.width * min(position / duration, 1) : 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard duration > 0 else { return }
                        seek(duration * min(max(location.x / proxy.size.width, 0), 1))
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(Self.time(position))
                    Spacer()
                    Text(duration > 0 ? "-" + Self.time(max(duration - position, 0)) : "")
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(IslandStyle.tertiary)
            }
        }
    }

    static func time(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(IslandStyle.primary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The system's AirPlay and output picker.
private struct RoutePicker: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        view.setRoutePickerButtonColor(NSColor(IslandStyle.primary), for: .normal)
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}

struct Artwork: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Color(red: 1, green: 0.42, blue: 0.42), Color(red: 0.48, green: 0.18, blue: 0.97)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

/// Five bars bouncing while music plays. Core Animation runs them, so they cost no CPU.
struct PlayingBars: NSViewRepresentable {
    let isPlaying: Bool

    func makeNSView(context: Context) -> BarsView { BarsView() }

    func updateNSView(_ view: BarsView, context: Context) {
        view.setPlaying(isPlaying)
    }

    final class BarsView: NSView {
        private var bars: [CALayer] = []
        private static let heights: [CGFloat] = [6, 12, 9, 14, 7]

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            for (index, height) in Self.heights.enumerated() {
                let bar = CALayer()
                bar.backgroundColor = NSColor(IslandStyle.volt).cgColor
                bar.cornerRadius = 1.5
                bar.bounds = CGRect(x: 0, y: 0, width: 3, height: height)
                layer?.addSublayer(bar)
                bars.append(bar)
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override var intrinsicContentSize: NSSize { NSSize(width: 23, height: 14) }

        /// Centred in whatever height the island gives, growing up and down from the middle.
        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let originX = (bounds.width - 23) / 2
            for (index, bar) in bars.enumerated() {
                bar.position = CGPoint(x: originX + CGFloat(index) * 5 + 1.5, y: bounds.midY)
            }
            CATransaction.commit()
        }

        func setPlaying(_ playing: Bool) {
            for (index, bar) in bars.enumerated() {
                if playing {
                    guard bar.animation(forKey: "bounce") == nil else { continue }
                    let animation = CABasicAnimation(keyPath: "transform.scale.y")
                    animation.fromValue = 0.35
                    animation.toValue = 1
                    animation.duration = 0.45 + Double(index % 3) * 0.12
                    animation.autoreverses = true
                    animation.repeatCount = .infinity
                    animation.timeOffset = Double(index) * 0.17
                    bar.add(animation, forKey: "bounce")
                } else {
                    bar.removeAnimation(forKey: "bounce")
                }
            }
        }
    }
}
