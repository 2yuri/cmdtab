import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Tiling (beta): Scroll Lock, spacing, dimming, keys, and the remembered sizes subpage.
struct TilingPane: View {
    @Bindable var preferences: Preferences

    private static var minimumPadding: Double { Double(ScreenPadding.minimumForMainScreen.rounded()) }
    @State private var subpage: Subpage?

    private enum Subpage {
        case rememberedSizes, floatingApps

        var title: String {
            switch self {
            case .rememberedSizes: "Remembered Sizes"
            case .floatingApps: "Floating Apps"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 12)
            switch subpage {
            case .rememberedSizes: RememberedSizesView(preferences: preferences)
            case .floatingApps: FloatingAppsView(preferences: preferences)
            case nil: settings
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let subpage {
                Button { self.subpage = nil } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 22, height: 22)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to Tiling")
                Text("Tiling ›").foregroundStyle(.tertiary)
                Text(subpage.title)
            } else {
                Text("Tiling")
                Text("BETA")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.volt, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .font(.title2.weight(.semibold))
        .accessibilityAddTraits(.isHeader)
    }

    private var floatingSummary: String {
        let count = preferences.floatingApps.count
        let apps = "\(count) \(count == 1 ? "app" : "apps")"
        guard preferences.floatsSystemApps else { return count == 0 ? "None" : apps }
        return count == 0 ? "System apps" : "System apps + \(count)"
    }

    private var settings: some View {
        Form {
            Section("Scroll Lock") {
                Toggle(isOn: $preferences.scrollLockEnabled) {
                    Text("Scroll Lock")
                    Text("Each window on this desktop becomes a full-height column on a strip that scrolls sideways to keep the focused window in view.")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Default column width")
                    Text("For windows you haven't sized yet.").font(.caption).foregroundStyle(.secondary)
                    SizeChooser(options: ColumnWidth.allCases, selection: $preferences.defaultColumnWidth)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Default height in a stack")
                    Text("When two or three windows share a column. 100% keeps it alone in its column.")
                        .font(.caption).foregroundStyle(.secondary)
                    SizeChooser(options: StackHeight.settingsChoices, selection: $preferences.defaultStackHeight)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Stack by dragging")
                    Text("Drop a window on the top or bottom half of another column (or at the screen's edge for the next one) to share it. ⌃⌥S always stacks.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Stack by dragging", selection: $preferences.dragToStack) {
                        ForEach(DragToStack.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                Toggle(isOn: $preferences.arrangePreviews) {
                    Text("Window previews in Arrange mode")
                    Text("The numbered tiles show a snapshot of each window. Needs Screen Recording, used only while Arrange mode is on.")
                }
                .onChange(of: preferences.arrangePreviews) { _, on in
                    if on && !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
                }

                Button { subpage = .rememberedSizes } label: {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Text("\(preferences.rememberedSizes.count) \(preferences.rememberedSizes.count == 1 ? "app" : "apps")")
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    } label: {
                        Text("Remembered sizes")
                        Text("Width and height you set, kept per app.")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { subpage = .floatingApps } label: {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Text(floatingSummary)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    } label: {
                        Text("Floating apps")
                        Text("Apps Scroll Lock leaves alone. Their windows stay where you put them.")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Picker("Centre the focused column", selection: $preferences.centreMode) {
                    ForEach(CentreMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle(isOn: $preferences.animatesScrolling) {
                    Text("Animate scrolling")
                    Text("The strip slides smoothly when focus moves, even across several columns. Off: it jumps straight there.")
                }

                LabeledContent {
                    HStack(spacing: 8) {
                        Image(systemName: "tortoise").foregroundStyle(.tertiary)
                        Slider(value: $preferences.animationSpeed, in: 0.5...2).frame(width: 130)
                        Image(systemName: "hare").foregroundStyle(.tertiary)
                        Text(String(format: "%.1f×", preferences.animationSpeed))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                } label: {
                    Text("Animation speed")
                    Text("Slower or faster slides and scrolls.")
                }
                .disabled(!preferences.animatesScrolling)

                Toggle(isOn: $preferences.wrapsAround) {
                    Text("Wrap around")
                    Text("From the first column, ⌃⌥← goes to the last one, and ⌃⌥→ from the last goes back to the first.")
                }

                SliderRow(
                    title: "Gap",
                    detail: "Space between columns in Scroll Lock.",
                    value: $preferences.tilingGap,
                    range: 0...32,
                    format: { "\(Int($0)) pt" }
                )
            }

            Section("Screen padding") {
                Toggle(isOn: $preferences.keepsWindowsOffEdges) {
                    Text("Keep windows off the screen edges")
                    Text("Every window stays this far from the edges, with or without Scroll Lock. Maximized and zoomed windows too.")
                }
                SliderRow(
                    title: "Padding",
                    detail: "Your desktop shows through around the windows. Measured from the screen's edges, so it's never less than the menu bar.",
                    value: Binding(
                        get: { max(preferences.tilingPadding, Self.minimumPadding) },
                        set: { preferences.tilingPadding = $0 }
                    ),
                    range: Self.minimumPadding...max(64, Self.minimumPadding + 32),
                    format: { "\(Int($0)) pt" }
                )
                .disabled(!preferences.keepsWindowsOffEdges)
            }

            Section("Focus") {
                Toggle(isOn: $preferences.dimsOtherWindows) {
                    Text("Dim other windows")
                    Text("A dark layer covers everything behind the focused window.")
                }
                SliderRow(title: "Dim amount", detail: nil, value: $preferences.dimAmount, range: 0.1...0.8, format: { "\(Int(($0 * 100).rounded()))%" })
                    .disabled(!preferences.dimsOtherWindows)
                LabeledContent {
                    Slider(value: .constant(1), in: 0...1).frame(width: 150).disabled(true)
                } label: {
                    Text("Window transparency")
                    Text("Makes unfocused windows see-through. Needs System Integrity Protection partly turned off, so it's unavailable.")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                LabeledContent {
                    KeyCaps(keys: ["⌃", "⌥", "A"])
                } label: {
                    Text("Arrange mode")
                    Text("On until you press it again or esc. Numbers the columns: ← → move the focused one, ⇧← ⇧→ to the start or end, ↑ ↓ width, ⌘← ⌘→ stack with the column on that side, ⇧↑ ⇧↓ height in a stack, ⌘↓ unstack, ⌘1–9 focus, drag a tile to reorder.")
                }
                LabeledContent("Focus column") { KeyCaps(keys: ["⌃", "⌥", "←", "→"]) }
                LabeledContent {
                    HStack(spacing: 6) {
                        KeyCaps(keys: ["⌃", "⌥"])
                        Text("+ scroll").foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Scroll the strip")
                    Text("Hold ⌃⌥ and scroll or swipe sideways. Without ⌃⌥, scrolling works as usual.")
                }
                LabeledContent("Move column") { KeyCaps(keys: ["⌃", "⌥", "⇧", "←", "→"]) }
                LabeledContent("Cycle column width") { KeyCaps(keys: ["⌃", "⌥", "R"]) }
                LabeledContent("Cycle height in a stack") { KeyCaps(keys: ["⌃", "⌥", "⇧", "R"]) }
                LabeledContent {
                    KeyCaps(keys: ["⌃", "⌥", "S"])
                } label: {
                    Text("Stack or unstack")
                    Text("Puts the focused window under the column on its left. Press again to take it out. Or just drag one window onto another.")
                }
                LabeledContent("Focus within a stack") { KeyCaps(keys: ["⌃", "⌥", "↑", "↓"]) }
            } header: {
                Text("Keys")
            } footer: {
                Text("Scroll Lock only arranges windows on the current desktop. Floating panels and dialogs are left alone. Drag a window onto the top or bottom half of another to stack them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Settings → Tiling › Remembered Sizes: per-app widths and heights, searchable.
private struct RememberedSizesView: View {
    @Bindable var preferences: Preferences
    @State private var query = ""

    private var filtered: [RememberedSize] {
        let sizes = preferences.rememberedSizes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !query.isEmpty else { return sizes }
        return sizes.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("Search apps", text: $query).textFieldStyle(.plain)
                }
            }

            Section {
                if filtered.isEmpty {
                    Text(preferences.rememberedSizes.isEmpty
                        ? "Nothing yet. Size a window with ⌃⌥R or by dragging its edge and it shows up here."
                        : "No app matches “\(query)”.")
                        .foregroundStyle(.secondary)
                }
                ForEach(filtered) { size in
                    RememberedSizeRow(preferences: preferences, bundleID: size.bundleID)
                }
            } header: {
                HStack {
                    Text("\(preferences.rememberedSizes.count) \(preferences.rememberedSizes.count == 1 ? "app" : "apps")")
                    Spacer()
                    if !preferences.rememberedSizes.isEmpty {
                        Button("Forget all") { preferences.rememberedSizes.removeAll() }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            } footer: {
                Text("Change a size here, or on the window with ⌃⌥R (width) and ⌃⌥⇧R (height in a stack). Forgetting an app sends its new windows back to the defaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Settings → Tiling › Floating Apps: apps whose windows never join the strip.
private struct FloatingAppsView: View {
    @Bindable var preferences: Preferences
    @State private var query = ""

    private var filtered: [FloatingApp] {
        let apps = preferences.floatingApps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $preferences.floatsSystemApps) {
                    Text("Float macOS system apps")
                    Text("Finder, System Settings, Calculator, Activity Monitor and the other apps that come with macOS. Safari still tiles.")
                }
                Toggle(isOn: $preferences.hidesFloatingApps) {
                    Text("Hide them when you go back to the strip")
                    Text("Like ⌘H: floating windows step aside so they don't sit on top of the columns. ⌘⇥ to one brings it back.")
                }
            }

            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("Search apps", text: $query).textFieldStyle(.plain)
                }
            }

            Section {
                if filtered.isEmpty {
                    Text(preferences.floatingApps.isEmpty ? "No apps yet. Add one with + Add app." : "No app matches “\(query)”.")
                        .foregroundStyle(.secondary)
                }
                ForEach(filtered) { app in
                    HStack(spacing: 12) {
                        Image(nsImage: AppIcon.image(for: app.bundleID))
                            .resizable()
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name)
                            Text(app.bundleID)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button { preferences.floatingApps.removeAll { $0.id == app.id } } label: {
                            Image(systemName: "xmark").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Tile \(app.name) again")
                    }
                }
            } header: {
                HStack {
                    Text("Your apps")
                    Spacer()
                    Button { addApps() } label: { Label("Add app", systemImage: "plus") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }
            } footer: {
                Text("Dialogs, sheets and fixed-size windows always float. Add an app with + and its windows leave the strip; remove it to tile them again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier,
                  !preferences.floatingApps.contains(where: { $0.bundleID == bundleID })
            else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            preferences.floatingApps.append(FloatingApp(bundleID: bundleID, name: name))
        }
    }
}

private enum AppIcon {
    static func image(for bundleID: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSWorkspace.shared.icon(for: .application)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct RememberedSizeRow: View {
    @Bindable var preferences: Preferences
    let bundleID: String

    private var size: RememberedSize? { preferences.rememberedSize(for: bundleID) }

    var body: some View {
        if let size {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(nsImage: AppIcon.image(for: bundleID))
                        .resizable()
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)
                    Text(size.name)
                    Spacer()
                    Button { preferences.forgetSize(of: bundleID) } label: {
                        Image(systemName: "xmark").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Forget \(size.name)")
                }
                HStack(spacing: 10) {
                    Text("Width").font(.caption).foregroundStyle(.tertiary).frame(width: 40, alignment: .leading)
                    SizeChooser(
                        options: ColumnWidth.allCases,
                        selection: Binding(
                            get: { size.width ?? preferences.defaultColumnWidth },
                            set: { preferences.remember(width: $0, bundleID: bundleID, name: size.name) }
                        ),
                        compact: true
                    )
                }
                .padding(.leading, 32)
                HStack(spacing: 10) {
                    Text("Height").font(.caption).foregroundStyle(.tertiary).frame(width: 40, alignment: .leading)
                    SizeChooser(
                        options: StackHeight.settingsChoices,
                        selection: Binding(
                            get: { size.height ?? preferences.defaultStackHeight },
                            set: { preferences.remember(height: $0, bundleID: bundleID, name: size.name) }
                        ),
                        compact: true
                    )
                }
                .padding(.leading, 32)
            }
            .padding(.vertical, 2)
        }
    }

}

private struct SliderRow: View {
    let title: String
    let detail: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(value: $value, in: range).frame(width: 150)
                Text(format(value))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        } label: {
            Text(title)
            if let detail { Text(detail) }
        }
    }
}

// MARK: - Size chooser

/// A width or height a window can take, drawn as a screen split into equal parts.
protocol SizeOption: Hashable {
    var label: String { get }
    var glyphCells: (total: Int, filled: Int) { get }
    static var glyphAxis: Axis { get }
}

extension ColumnWidth: SizeOption {
    static var glyphAxis: Axis { .horizontal }
}

extension StackHeight: SizeOption {
    static var glyphAxis: Axis { .vertical }
}

/// Segmented control whose segments show how much of the screen each choice takes.
struct SizeChooser<Option: SizeOption>: View {
    let options: [Option]
    @Binding var selection: Option
    var compact = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button { selection = option } label: {
                    HStack(spacing: 6) {
                        SizeGlyph(cells: option.glyphCells, axis: Option.glyphAxis, isSelected: isSelected)
                        Text(option.label)
                            .font(.system(size: compact ? 12 : 13, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                    .padding(.horizontal, compact ? 7 : 10)
                    .padding(.vertical, compact ? 4 : 5)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .fixedSize()
    }
}

private struct SizeGlyph: View {
    let cells: (total: Int, filled: Int)
    let axis: Axis
    let isSelected: Bool

    var body: some View {
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 1.5)) : AnyLayout(VStackLayout(spacing: 1.5))
        layout {
            ForEach(0..<cells.total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(fill(isWindow: index < cells.filled))
            }
        }
        .padding(2)
        .frame(width: axis == .horizontal ? 30 : 16, height: axis == .horizontal ? 16 : 22)
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(isSelected ? Color.primary : Color.secondary.opacity(0.6), lineWidth: 1.2)
        )
        .accessibilityHidden(true)
    }

    private func fill(isWindow: Bool) -> Color {
        if isWindow { return isSelected ? .accentColor : .secondary.opacity(0.6) }
        return .primary.opacity(isSelected ? 0.08 : 0.05)
    }
}
