import Foundation
import IOKit.ps
import Observation

/// What the Effects setting asks for.
enum IslandEffect: String, CaseIterable {
    /// Follows the sky in the weather city: rain, snow, fireflies on a clear night, else nothing.
    case weather, rain, snow, fireflies, off

    var label: String {
        switch self {
        case .weather: "Weather"
        case .rain: "Rain"
        case .snow: "Snow"
        case .fireflies: "Fireflies"
        case .off: "Off"
        }
    }
}

/// Where the effect falls.
enum EffectPlacement: String, CaseIterable {
    case island, screen, both

    var label: String {
        switch self {
        case .island: "Island"
        case .screen: "Screen"
        case .both: "Both"
        }
    }
}

/// What's falling right now.
enum EffectKind: Equatable {
    case rain, snow, fireflies
}

/// Decides what falls, if anything: the setting, the weather city's sky, and the power source.
/// The particles themselves are Core Animation's, drawn by the GPU with no work per frame here.
@MainActor
@Observable
final class IslandEffects {
    private let preferences: Preferences
    private let weather: WeatherService
    /// On battery (with Pause on battery) or in Low Power Mode.
    private(set) var isPaused = false

    @ObservationIgnored private var weatherTimer: Timer?
    @ObservationIgnored private var powerSource: CFRunLoopSource?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(preferences: Preferences, weather: WeatherService) {
        self.preferences = preferences
        self.weather = weather
    }

    /// What falls now, or nil.
    var kind: EffectKind? {
        guard preferences.isIslandModuleOn(.effects), !isPaused else { return nil }
        switch preferences.islandEffect {
        case .off: return nil
        case .rain: return .rain
        case .snow: return .snow
        case .fireflies: return .fireflies
        case .weather:
            guard let report = weather.report else { return nil }
            return Self.kind(code: report.code, isDay: report.isDay)
        }
    }

    var onScreen: Bool { preferences.islandEffectPlacement != .island }
    /// What falls in the island's wings: nothing when the effect is for the screen only.
    var islandKind: EffectKind? { preferences.islandEffectPlacement == .screen ? nil : kind }
    var style: EffectStyle {
        EffectStyle(
            amount: preferences.islandEffectAmount,
            size: preferences.islandEffectSize,
            speed: preferences.islandEffectSpeed,
            opacity: preferences.islandEffectOpacity,
            angle: preferences.islandEffectAngle,
            fireflyColor: preferences.islandEffectFireflyColor
        )
    }

    /// Whether the effect can slant.
    nonisolated static func slants(_ effect: IslandEffect) -> Bool {
        effect == .rain || effect == .snow || effect == .weather
    }

    /// WMO weather codes to what falls: rain for drizzle, rain and storms, snow for snow, fireflies
    /// on a clear night.
    nonisolated static func kind(code: Int, isDay: Bool) -> EffectKind? {
        switch code {
        case 51...67, 80...82, 95...99: .rain
        case 71...77, 85, 86: .snow
        case 0, 1: isDay ? nil : .fireflies
        default: nil
        }
    }

    /// Call when the settings change.
    func update() {
        let wanted = preferences.isIslandModuleOn(.effects) && preferences.islandEffect != .off
        if wanted { watchPower() } else { stopWatchingPower() }
        refreshPower()
        if wanted && preferences.islandEffect == .weather {
            startWeather()
        } else {
            weatherTimer?.invalidate()
            weatherTimer = nil
        }
    }

    /// Asks for the weather now and every 30 minutes, only while the effect follows it.
    private func startWeather() {
        weather.refreshIfNeeded(place: preferences.islandWeatherPlace)
        guard weatherTimer == nil else { return }
        let timer = Timer(timeInterval: WeatherService.freshFor, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.weather.refreshIfNeeded(place: self.preferences.islandWeatherPlace)
            }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        weatherTimer = timer
    }

    // MARK: Power

    private func watchPower() {
        guard powerSource == nil else { return }
        if let source = IOPSNotificationCreateRunLoopSource({ _ in
            NotificationCenter.default.post(name: .cmdTabPowerSourceChanged, object: nil)
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
        for name in [Notification.Name.cmdTabPowerSourceChanged, .NSProcessInfoPowerStateDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPower() }
            })
        }
    }

    private func stopWatchingPower() {
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private func refreshPower() {
        let paused = ProcessInfo.processInfo.isLowPowerModeEnabled
            || (preferences.islandEffectPausesOnBattery && Self.isOnBattery())
        if paused != isPaused { isPaused = paused }
    }

    nonisolated static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }
}

extension Notification.Name {
    static let cmdTabPowerSourceChanged = Notification.Name("CmdTabPowerSourceChanged")
}
