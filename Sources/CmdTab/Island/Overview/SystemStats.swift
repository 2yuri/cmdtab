import Darwin
import Foundation
import IOKit.ps
import Observation

/// CPU, memory and battery for the Overview tab. Sampled once a second, and only while the tab is
/// on screen: `start()` when it appears, `stop()` when it goes.
@MainActor
@Observable
final class SystemStats {
    nonisolated struct Battery: Equatable {
        var percent: Int
        /// Minutes left on battery, when macOS has worked it out.
        var minutesLeft: Int?
        var isCharging: Bool
    }

    /// Recent samples, oldest first, 0…1.
    private(set) var cpu: [Double] = []
    private(set) var memory: [Double] = []
    private(set) var battery: Battery?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTicks: CPUTicks?

    nonisolated static let sampleCount = 30

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        lastTicks = Self.cpuTicks()
        sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastTicks = nil
    }

    private func sample() {
        if let ticks = Self.cpuTicks() {
            if let last = lastTicks, let usage = ticks.usage(since: last) {
                cpu = Self.appending(usage, to: cpu)
            }
            lastTicks = ticks
        }
        if let used = Self.memoryUsed() { memory = Self.appending(used, to: memory) }
        let battery = Self.readBattery()
        if battery != self.battery { self.battery = battery }
    }

    nonisolated static func appending(_ value: Double, to samples: [Double]) -> [Double] {
        Array((samples + [min(max(value, 0), 1)]).suffix(sampleCount))
    }

    // MARK: Reading

    nonisolated struct CPUTicks: Equatable {
        var busy: UInt64
        var total: UInt64

        /// The share of time spent busy since `earlier`.
        func usage(since earlier: CPUTicks) -> Double? {
            guard total > earlier.total else { return nil }
            return Double(busy &- earlier.busy) / Double(total - earlier.total)
        }
    }

    nonisolated static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return CPUTicks(busy: user + system + nice, total: user + system + idle + nice)
    }

    /// Memory in use the way Activity Monitor counts it: app memory, wired and compressed.
    nonisolated static func memoryUsed() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let appPages = UInt64(stats.internal_page_count), purgeable = UInt64(stats.purgeable_count)
        let pages = (appPages > purgeable ? appPages - purgeable : 0)
            + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return nil }
        return Double(pages * UInt64(getpagesize())) / Double(total)
    }

    nonisolated static func readBattery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let minutes = description[kIOPSTimeToEmptyKey] as? Int
            return Battery(
                percent: Int((Double(current) / Double(maximum) * 100).rounded()),
                minutesLeft: !charging && (minutes ?? -1) > 0 ? minutes : nil,
                isCharging: charging
            )
        }
        return nil
    }
}
