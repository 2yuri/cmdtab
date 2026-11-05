import AppKit
import Darwin
import Observation

/// What each app is using, for the CPU and Memory popovers in the Overview tab. Helpers (web
/// content, renderers, plug-ins) count towards the app responsible for them, the way Activity
/// Monitor groups them. Read every two seconds, and only while a popover is open.
@MainActor
@Observable
final class AppUsage {
    nonisolated enum Resource: Equatable {
        case cpu, memory
    }

    struct Entry: Identifiable, Equatable {
        let pid: pid_t
        let name: String
        let icon: NSImage?
        /// CPU: share of the whole Mac, 0…1. Memory: bytes.
        let value: Double
        var id: pid_t { pid }

        static func == (lhs: Entry, rhs: Entry) -> Bool {
            lhs.pid == rhs.pid && lhs.value == rhs.value && lhs.name == rhs.name
        }
    }

    /// The heaviest apps first.
    private(set) var cpu: [Entry] = []
    private(set) var memory: [Entry] = []

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var last: Snapshot?
    @ObservationIgnored private var reading = false

    nonisolated static let shown = 5

    func start() {
        guard timer == nil else { return }
        read()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        last = nil
    }

    #if DEBUG
    func preview(cpu: [Entry], memory: [Entry]) {
        self.cpu = cpu
        self.memory = memory
    }
    #endif

    func entries(for resource: Resource) -> [Entry] {
        resource == .cpu ? cpu : memory
    }

    /// Asks the app to quit, the way ⌘Q would.
    func quit(_ entry: Entry) {
        NSRunningApplication(processIdentifier: entry.pid)?.terminate()
        cpu.removeAll { $0.pid == entry.pid }
        memory.removeAll { $0.pid == entry.pid }
    }

    private func read() {
        guard !reading else { return }
        reading = true
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { App(pid: $0.processIdentifier, name: $0.localizedName ?? "") }
        Task.detached(priority: .utility) {
            let snapshot = Self.snapshot(apps: apps)
            await MainActor.run { [weak self] in
                self?.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: Snapshot) {
        reading = false
        guard timer != nil else { return }
        let names = Dictionary(snapshot.apps.map { ($0.pid, $0.name) }, uniquingKeysWith: { first, _ in first })
        func entry(_ pid: pid_t, _ value: Double) -> Entry {
            let app = NSRunningApplication(processIdentifier: pid)
            return Entry(pid: pid, name: names[pid] ?? "", icon: app?.icon, value: value)
        }
        if let last {
            let shares = Self.cpuShares(from: last, to: snapshot)
            cpu = Self.top(shares).map { entry($0.key, $0.value) }
        }
        memory = Self.top(Self.bytes(snapshot.memory)).map { entry($0.key, $0.value) }
        let first = last == nil
        last = snapshot
        // CPU needs two readings: take the second soon, so the list isn't empty for long.
        if first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.read() }
        }
    }

    /// Footprints as numbers (not reinterpreted bits).
    nonisolated static func bytes(_ memory: [pid_t: UInt64]) -> [pid_t: Double] {
        memory.mapValues { Double($0) }
    }

    nonisolated static func top(_ values: [pid_t: Double]) -> [(key: pid_t, value: Double)] {
        Array(values.filter { $0.value > 0 }.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.prefix(shown))
    }

    // MARK: Reading

    nonisolated struct App: Sendable {
        let pid: pid_t
        let name: String
    }

    nonisolated struct Snapshot: Sendable {
        let apps: [App]
        /// CPU time used so far by each app and its helpers, in nanoseconds.
        let cpuTime: [pid_t: UInt64]
        /// Memory footprint of each app and its helpers, in bytes.
        let memory: [pid_t: UInt64]
        let taken: UInt64
    }

    /// Each app's share of the whole Mac between two snapshots, 0…1.
    nonisolated static func cpuShares(from earlier: Snapshot, to later: Snapshot) -> [pid_t: Double] {
        let elapsed = Double(later.taken &- earlier.taken) * Double(ProcessInfo.processInfo.activeProcessorCount)
        guard elapsed > 0 else { return [:] }
        var shares: [pid_t: Double] = [:]
        for (pid, time) in later.cpuTime {
            guard let before = earlier.cpuTime[pid], time >= before else { continue }
            shares[pid] = min(Double(time - before) / elapsed, 1)
        }
        return shares
    }

    nonisolated static func snapshot(apps: [App]) -> Snapshot {
        let appPids = Set(apps.map(\.pid))
        var cpuTime: [pid_t: UInt64] = [:]
        var memory: [pid_t: UInt64] = [:]
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        for pid in allPids() {
            guard let owner = owner(of: pid, apps: appPids) else { continue }
            var info = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard result == 0 else { continue }
            let ticks = info.ri_user_time + info.ri_system_time
            let nanos = ticks * UInt64(timebase.numer) / UInt64(max(timebase.denom, 1))
            cpuTime[owner, default: 0] += nanos
            memory[owner, default: 0] += info.ri_phys_footprint
        }
        return Snapshot(apps: apps, cpuTime: cpuTime, memory: memory, taken: DispatchTime.now().uptimeNanoseconds)
    }

    nonisolated private static func allPids() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return Array(pids.prefix(Int(max(found, 0)))).filter { $0 > 0 }
    }

    /// The app a process works for: itself, the app macOS holds responsible for it, or an app up
    /// its parent chain.
    nonisolated private static func owner(of pid: pid_t, apps: Set<pid_t>) -> pid_t? {
        if apps.contains(pid) { return pid }
        if let responsible = responsiblePid?(pid), apps.contains(responsible) { return responsible }
        var current = pid
        for _ in 0..<4 {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            let parent = pid_t(info.pbi_ppid)
            if apps.contains(parent) { return parent }
            if parent <= 1 { return nil }
            current = parent
        }
        return nil
    }

    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t
    nonisolated(unsafe) private static let responsiblePid: ((pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        let function = unsafeBitCast(symbol, to: ResponsibleFunction.self)
        return { function($0) }
    }()
}
