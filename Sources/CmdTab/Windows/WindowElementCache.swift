import AppKit

/// Remembers the Accessibility elements of windows on other Spaces (full-screen apps, the desktop
/// behind one), which apps leave out of `kAXWindowsAttribute`.
///
/// Finding one means asking the app for its element ids one by one, and a browser that has been open
/// for a while has thousands. So each switcher invocation scans only a small, time-boxed stretch and
/// the next one carries on from there. New windows always get higher ids than the ones scanned, so
/// nothing is missed, and an element found once is kept until its window or app goes away.
@MainActor
final class WindowElementCache {
    static let shared = WindowElementCache()

    /// About 35 ms: what one ⌘⇥ may spend per app.
    static let listBudget: UInt64 = 3_000
    /// About 250 ms, once, when the chosen window's element is still unknown.
    static let commitBudget: UInt64 = 20_000

    private var elements: [pid_t: [CGWindowID: AXUIElement]] = [:]
    private var scannedTo: [pid_t: UInt64] = [:]
    private var scanningInBackground: Set<pid_t> = []

    /// Keeps an element the app handed out the normal way.
    func remember(_ element: AXUIElement, windowID: CGWindowID, pid: pid_t) {
        elements[pid, default: [:]][windowID] = element
    }

    /// The elements of `windowIDs` that are known, scanning up to `budget` more ids for missing ones.
    func elements(pid: pid_t, windowIDs: Set<CGWindowID>, budget: UInt64) -> [CGWindowID: AXUIElement] {
        var known = elements[pid] ?? [:]
        let missing = windowIDs.subtracting(known.keys)
        if !missing.isEmpty, let range = ElementScan.next(after: scannedTo[pid] ?? 0, budget: budget) {
            let scan = PrivateAPI.windowElements(pid: pid, in: range, wanted: missing)
            known.merge(scan.elements) { current, _ in current }
            scannedTo[pid] = scan.scannedTo
            elements[pid] = known
            if !missing.isSubset(of: known.keys) { continueInBackground(pid: pid, wanted: missing) }
        }
        return known.filter { windowIDs.contains($0.key) }
    }

    /// Carries on looking off the main thread, so the next ⌘⇥ has the element without waiting.
    private func continueInBackground(pid: pid_t, wanted: Set<CGWindowID>) {
        guard !scanningInBackground.contains(pid),
              let range = ElementScan.next(after: scannedTo[pid] ?? 0, budget: Self.commitBudget)
        else { return }
        scanningInBackground.insert(pid)
        Task.detached(priority: .utility) {
            let scan = PrivateAPI.windowElements(pid: pid, in: range, wanted: wanted)
            let found = UncheckedElements(scan.elements)
            await MainActor.run {
                let cache = WindowElementCache.shared
                cache.scanningInBackground.remove(pid)
                // Only if nothing else moved the scan on meanwhile.
                guard cache.scannedTo[pid] == range.lowerBound else { return }
                cache.elements[pid, default: [:]].merge(found.value) { current, _ in current }
                cache.scannedTo[pid] = scan.scannedTo
            }
        }
    }

    /// Drops windows that closed and apps that quit.
    func prune(liveWindowIDs: Set<CGWindowID>, livePIDs: Set<pid_t>) {
        for pid in elements.keys where !livePIDs.contains(pid) {
            elements[pid] = nil
            scannedTo[pid] = nil
        }
        for pid in elements.keys {
            elements[pid] = elements[pid]?.filter { liveWindowIDs.contains($0.key) }
        }
    }
}

/// Which element ids to scan next. Pure, so it can be tested.
enum ElementScan {
    /// Past this, an app is assumed to have no more windows to find.
    static let ceiling: UInt64 = 500_000

    static func next(after scanned: UInt64, budget: UInt64) -> Range<UInt64>? {
        guard scanned < ceiling, budget > 0 else { return nil }
        return scanned..<min(scanned + budget, ceiling)
    }
}

/// AX elements are safe to use from any thread; this carries them back to the main actor.
private struct UncheckedElements: @unchecked Sendable {
    let value: [CGWindowID: AXUIElement]
    init(_ value: [CGWindowID: AXUIElement]) { self.value = value }
}
