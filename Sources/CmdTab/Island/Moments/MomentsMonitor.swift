import AppKit
import IOBluetooth
import IOKit.ps
import Observation

/// Something that happened, shown for a few seconds at the sides of the closed island.
struct Moment: Equatable {
    enum Kind: Equatable {
        case headphones, charging, lowBattery
    }

    let kind: Kind
    /// Shown on the left.
    let title: String
    /// Shown on the right.
    let value: String?
}

/// AirPods connecting and the charger going in or the battery running low. Both are system
/// notifications: nothing is checked on a timer.
@MainActor
@Observable
final class MomentsMonitor: NSObject {
    private(set) var current: Moment?

    @ObservationIgnored private var powerSource: CFRunLoopSource?
    @ObservationIgnored private var bluetooth: IOBluetoothUserNotification?
    @ObservationIgnored private var clearTimer: Timer?
    @ObservationIgnored private var wasCharging: Bool?
    @ObservationIgnored private var warnedLow: Int?

    static let duration: TimeInterval = 4

    func start() {
        guard powerSource == nil else { return }
        wasCharging = Self.battery()?.charging
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<MomentsMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.powerChanged() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
        bluetooth = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }

    func stop() {
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil
        bluetooth?.unregister()
        bluetooth = nil
        current = nil
    }

    private func show(_ moment: Moment) {
        current = moment
        clearTimer?.invalidate()
        clearTimer = Timer.scheduledTimer(withTimeInterval: Self.duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.current = nil }
        }
    }

    // MARK: Power

    private static func battery() -> (percent: Int, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let capacity = description[kIOPSCurrentCapacityKey] as? Int else { continue }
            let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return (capacity, onAC)
        }
        return nil
    }

    private func powerChanged() {
        guard let battery = Self.battery() else { return }
        if battery.charging, wasCharging == false {
            show(Moment(kind: .charging, title: "Charging", value: "\(battery.percent)%"))
            warnedLow = nil
        }
        wasCharging = battery.charging
        if !battery.charging, let threshold = [10, 20].first(where: { battery.percent <= $0 }), warnedLow != threshold {
            warnedLow = threshold
            show(Moment(kind: .lowBattery, title: "Battery low", value: "\(battery.percent)%"))
        }
    }

    // MARK: Headphones

    /// IOBluetooth calls this on a queue of its own, not the main thread: read the device here, then
    /// hop to the main actor to show it.
    @objc nonisolated private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // Audio devices only (headphones, speakers).
        guard device.deviceClassMajor == UInt32(kBluetoothDeviceClassMajorAudio) else { return }
        let moment = Moment(kind: .headphones, title: device.name ?? "Headphones", value: Self.batteryText(of: device))
        Task { @MainActor [weak self] in self?.show(moment) }
    }

    /// "L 82% R 78%" when the headphones report it.
    nonisolated private static func batteryText(of device: IOBluetoothDevice) -> String? {
        func percent(_ key: String) -> Int? {
            guard device.responds(to: NSSelectorFromString(key)), let value = device.value(forKey: key) as? NSNumber else { return nil }
            return value.intValue > 0 ? value.intValue : nil
        }
        if let left = percent("batteryPercentLeft"), let right = percent("batteryPercentRight") {
            return "L \(left)%  R \(right)%"
        }
        return percent("batteryPercentSingle").map { "\($0)%" }
    }
}
