import SwiftUI

/// The open Windows tab: this desktop's windows, most recent first. Click one to switch to it.
/// The list is built when the tab opens, the same way ⌘⇥ builds it; nothing runs while it's closed.
struct WindowsTab: View {
    let source: IslandWindowSource
    @State private var windows: [SwitcherWindow] = []
    @State private var query = ""
    @FocusState private var searching: Bool

    /// The same matching as the switcher's search: window title and app name.
    private var shown: [SwitcherWindow] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return windows }
        return windows.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.appName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TabHeader(title: "This desktop") {
                Text("\(windows.count) \(windows.count == 1 ? "window" : "windows")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IslandStyle.secondary)
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium))
                TextField("Search windows", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searching)
                    .onSubmit { if let first = shown.first { source.activate(first) } }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)) }
                        .buttonStyle(.plain)
                }
            }
            .foregroundStyle(IslandStyle.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            WindowList(windows: shown, query: query) { source.activate($0) }
        }
        .onAppear { windows = source.windows() }
    }
}

private struct WindowList: View {
    let windows: [SwitcherWindow]
    let query: String
    let open: (SwitcherWindow) -> Void

    var body: some View {
        if windows.isEmpty {
            Text(query.isEmpty ? "No windows on this desktop" : "No windows match")
                .font(.system(size: 13))
                .foregroundStyle(IslandStyle.secondary)
                .padding(.vertical, 8)
        } else if windows.count > 6 {
            ScrollView { rows }.scrollIndicators(.never).frame(height: 6 * 46)
        } else {
            rows
        }
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(Array(windows.enumerated()), id: \.element.windowID) { index, window in
                WindowRow(window: window, isCurrent: index == 0 && query.isEmpty) { open(window) }
            }
        }
    }
}

private struct WindowRow: View {
    let window: SwitcherWindow
    let isCurrent: Bool
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                if let icon = window.icon {
                    Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(window.title.isEmpty ? window.appName : window.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(IslandStyle.primary.opacity(window.isDimmed ? 0.5 : 1))
                        .lineLimit(1)
                    Text(window.appName).font(.system(size: 11)).foregroundStyle(IslandStyle.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if isCurrent {
                    Text("Now").font(.system(size: 11, weight: .semibold)).foregroundStyle(IslandStyle.volt)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isCurrent || hovering ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Lists and switches windows for the island, with the switcher's own rules.
@MainActor
final class IslandWindowSource {
    private let preferences: Preferences
    private lazy var provider = WindowProvider()

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func windows() -> [SwitcherWindow] {
        var options = preferences.windowFilter
        options.scope = .currentSpace
        return Array(provider.windows(options: options).prefix(12))
    }

    func activate(_ window: SwitcherWindow) {
        WindowActivator.activate(window)
    }
}
