import Foundation

/// Everything the island shows, started and stopped with its module so a module that's off costs
/// nothing.
@MainActor
final class IslandServices {
    let agents = AgentMonitor()
    let music = NowPlayingMonitor()
    let shelf = ShelfStore()
    let focus = FocusTimer()
    let calendar = CalendarStore()
    let weather = WeatherService()
    let meetings = MeetingWatcher()
    let moments = MomentsMonitor()
    /// CPU, memory and battery for the Overview, sampled only while it's open.
    let stats = SystemStats()
    let appUsage = AppUsage()
    let windowDrop = WindowDropWatcher()
    /// Tiling's: a tiled window dragged up to the island.
    var notchDrop: NotchDrop?
    let windows: IslandWindowSource
    /// Rain, snow or fireflies.
    let effects: IslandEffects

    init(preferences: Preferences) {
        windows = IslandWindowSource(preferences: preferences)
        effects = IslandEffects(preferences: preferences, weather: weather)
    }

    func update(_ preferences: Preferences) {
        let on = { preferences.isIslandModuleOn($0) }
        // The Overview shows agents and music too, so it keeps their readers running.
        if on(.agents) || on(.overview) {
            agents.notifies = preferences.islandNotifies
            agents.start()
        } else {
            agents.stop()
        }
        agents.setApprovals(on(.agents) && preferences.islandApprovals)
        if on(.music) || on(.overview) { music.start() } else { music.stop() }
        if !on(.overview) { stats.stop(); appUsage.stop() }
        shelf.setWatchesNewFiles(on(.shelf) && preferences.islandWatchesNewFiles)
        if on(.meetings) { meetings.start() } else { meetings.stop() }
        if on(.moments) { moments.start() } else { moments.stop() }
        if !on(.focus) { focus.reset() }
        if !on(.calendar) { calendar.stop() }
        // The Weather effect keeps asking for the sky even with the tab off.
        if !on(.weather) && !(on(.effects) && preferences.islandEffect == .weather) { weather.clear() }
        effects.update()
        // Dragging a window to the island arranges it like Tiling would: on with Windows, off while
        // Tiling places the windows itself.
        windowDrop.screenPadding = { preferences.screenPadding }
        if on(.windows) && !preferences.scrollLockEnabled { windowDrop.start() } else { windowDrop.stop() }
        notchDrop?.isEnabled = preferences.islandEnabled && on(.windows) && preferences.scrollLockEnabled
    }
}
