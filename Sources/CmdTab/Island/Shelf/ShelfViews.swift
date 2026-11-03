import AppKit
import SwiftUI

/// The open Shelf tab: drop zone, held files you can drag out, and actions.
struct ShelfTab: View {
    let shelf: ShelfStore
    /// A file is being dragged over the open island.
    var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabHeader(title: "Shelf") {
                Text("Kept 24 h").font(.system(size: 12, weight: .medium)).foregroundStyle(IslandStyle.secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.to.line").font(.system(size: 14, weight: .semibold))
                Text("Drop files here to hold them").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(IslandStyle.volt)
            .frame(maxWidth: .infinity)
            .frame(height: shelf.items.isEmpty ? 84 : 52)
            .background(IslandStyle.volt.opacity(isTargeted ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(IslandStyle.volt.opacity(isTargeted ? 1 : 0.55), style: StrokeStyle(lineWidth: isTargeted ? 1.6 : 1.2, dash: isTargeted ? [] : [5, 4]))
            )
            .animation(.easeOut(duration: 0.15), value: isTargeted)
            if !shelf.items.isEmpty {
                let rows = VStack(spacing: 2) {
                    ForEach(shelf.items) { item in
                        ShelfRow(item: item) { shelf.remove(item) }
                    }
                }
                if shelf.items.count > 5 {
                    ScrollView { rows }.scrollIndicators(.never).frame(height: 5 * 44)
                } else {
                    rows
                }
                HStack(spacing: 6) {
                    ShelfAction(title: "AirDrop", symbol: "dot.radiowaves.left.and.right") { shelf.airDrop() }
                    ShelfAction(title: "Copy all", symbol: "doc.on.doc") { shelf.copyAll() }
                    ShelfAction(title: "Clear", symbol: "trash") { shelf.clear() }
                    Spacer()
                }
            }
        }
    }
}

private struct ShelfRow: View {
    let item: ShelfItem
    let remove: () -> Void
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            // The whole row but the remove button is the drag handle (an AppKit view on top).
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                    .resizable()
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(IslandStyle.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(meta)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(IslandStyle.tertiary)
                }
                Spacer(minLength: 0)
            }
            .overlay(FileDragSource(url: item.url))
            Button {
                ShelfStore.copyToClipboard(item.url)
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(copied ? IslandStyle.volt : IslandStyle.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy")
            .opacity(hovering || copied ? 1 : 0)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(IslandStyle.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(hovering ? Color.white.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
    }

    private var meta: String {
        let size = (try? item.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        let sizeText = size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        let age = item.addedAt.formatted(.relativeShort)
        return [sizeText, age == "now" ? "just now" : "\(age) ago"].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct ShelfAction: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(IslandStyle.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// "Screenshot saved" / "Download finished", for a moment, when a file lands on the Shelf.
struct ArrivalView: View {
    let item: ShelfItem
    let count: Int
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                    .resizable()
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.isScreenshot(item) ? "Screenshot saved" : "Download finished")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(IslandStyle.primary)
                    Text("\(item.name) · on the Shelf")
                        .font(.system(size: 11))
                        .foregroundStyle(IslandStyle.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
            }
            .overlay(FileDragSource(url: item.url))
            Button {
                ShelfStore.copyToClipboard(item.url)
                copied = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10, weight: .semibold))
                    Text(copied ? "Copied" : "Copy").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(copied ? IslandStyle.volt : IslandStyle.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            HStack(spacing: 4) {
                Image(systemName: "tray").font(.system(size: 10, weight: .semibold))
                Text("\(count)").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(IslandStyle.volt)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(IslandStyle.volt.opacity(0.14), in: Capsule())
        }
    }

    static func isScreenshot(_ item: ShelfItem) -> Bool {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? ""
        return !item.path.hasPrefix(downloads)
    }
}
