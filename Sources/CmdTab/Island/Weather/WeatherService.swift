import Foundation
import Observation
import SwiftUI

/// A city picked for the weather, with its coordinates so it's never mixed up with another of the
/// same name.
struct WeatherPlace: Codable, Hashable, Identifiable {
    let name: String
    /// "Paraná, Brazil".
    let region: String
    let latitude: Double
    let longitude: Double

    var id: String { "\(latitude),\(longitude)" }

    static func parseSearch(_ data: Data) -> [WeatherPlace] {
        guard let results = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { result in
            guard let name = result["name"] as? String,
                  let latitude = result["latitude"] as? Double,
                  let longitude = result["longitude"] as? Double else { return nil }
            let region = [result["admin1"] as? String, result["country"] as? String].compactMap { $0 }.joined(separator: ", ")
            return WeatherPlace(name: name, region: region, latitude: latitude, longitude: longitude)
        }
    }
}

/// Weather for one city by name, from Open-Meteo (no account, no key). Only the city name is sent,
/// never your location. Asked only when the island opens and the last answer is over 30 minutes old.
@MainActor
@Observable
final class WeatherService {
    struct Hour: Equatable, Identifiable {
        let date: Date
        let temperature: Double
        let code: Int
        /// Chance of rain, 0…100.
        var rain = 0
        var id: Date { date }
    }

    struct Day: Equatable {
        let date: Date
        let high: Double
        let low: Double
    }

    struct Report: Equatable {
        let place: String
        let temperature: Double
        let high: Double
        let low: Double
        let code: Int
        let isDay: Bool
        /// From the current hour on, up to a week ahead.
        let hours: [Hour]
        var days: [Day] = []
        /// The first hour in the next six with rain likely, if any.
        let rainFrom: Date?
        let fetchedAt: Date
    }

    private(set) var report: Report?
    private(set) var failed = false
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var lastCity = ""

    static let freshFor: TimeInterval = 30 * 60

    var usesFahrenheit: Bool { Locale.current.measurementSystem == .us }

    /// Fetches if there's no fresh answer for `place`.
    func refreshIfNeeded(place: WeatherPlace?) {
        guard let place, !loading else { return }
        if place.id == lastCity, let report, Date.now.timeIntervalSince(report.fetchedAt) < Self.freshFor { return }
        loading = true
        lastCity = place.id
        let fahrenheit = usesFahrenheit
        Task {
            let result = try? await Self.fetch(place: place, fahrenheit: fahrenheit)
            loading = false
            failed = result == nil
            if let result { report = result }
        }
    }

    /// Cities matching what you typed, for the picker. Only runs while you type in it.
    static func search(_ query: String) async -> [WeatherPlace] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { return [] }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            .init(name: "name", value: query),
            .init(name: "count", value: "5"),
            .init(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en"),
        ]
        guard let (data, _) = try? await URLSession.shared.data(from: components.url!) else { return [] }
        return WeatherPlace.parseSearch(data)
    }

    #if DEBUG
    /// Screenshots and tests: a made-up report.
    func preview(_ report: Report) { self.report = report }
    #endif

    func clear() {
        report = nil
        lastCity = ""
    }

    private static func fetch(place: WeatherPlace, fahrenheit: Bool) async throws -> Report? {
        let latitude = place.latitude
        let longitude = place.longitude
        var forecast = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        forecast.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "7"),
            .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
        ]
        let (data, _) = try await URLSession.shared.data(from: forecast.url!)
        return parse(data, place: place.name, now: .now)
    }

    static func parse(_ data: Data, place: String, now: Date) -> Report? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = object["current"] as? [String: Any],
              let hourly = object["hourly"] as? [String: Any],
              let daily = object["daily"] as? [String: Any],
              let temperature = current["temperature_2m"] as? Double else { return nil }
        let times = (hourly["time"] as? [Double]) ?? []
        let temps = (hourly["temperature_2m"] as? [Double]) ?? []
        let codes = (hourly["weather_code"] as? [Int]) ?? []
        let rain = (hourly["precipitation_probability"] as? [Int?]) ?? []
        var hours: [Hour] = []
        var rainFrom: Date?
        for index in times.indices where index < temps.count && index < codes.count {
            let date = Date(timeIntervalSince1970: times[index])
            guard date > now.addingTimeInterval(-3600) else { continue }
            let chance = index < rain.count ? rain[index] ?? 0 : 0
            if rainFrom == nil, hours.count < 6, chance >= Self.likelyRain { rainFrom = date }
            hours.append(Hour(date: date, temperature: temps[index], code: codes[index], rain: chance))
        }
        let dayTimes = (daily["time"] as? [Double]) ?? []
        let highs = (daily["temperature_2m_max"] as? [Double]) ?? []
        let lows = (daily["temperature_2m_min"] as? [Double]) ?? []
        let days = dayTimes.indices.compactMap { index -> Day? in
            guard index < highs.count, index < lows.count else { return nil }
            return Day(date: Date(timeIntervalSince1970: dayTimes[index]), high: highs[index], low: lows[index])
        }
        return Report(
            place: place,
            temperature: temperature,
            high: (daily["temperature_2m_max"] as? [Double])?.first ?? temperature,
            low: (daily["temperature_2m_min"] as? [Double])?.first ?? temperature,
            code: current["weather_code"] as? Int ?? 0,
            isDay: (current["is_day"] as? Int ?? 1) == 1,
            hours: hours,
            days: days,
            rainFrom: rainFrom,
            fetchedAt: now
        )
    }

    /// A chance of rain from here on counts as "rain likely".
    nonisolated static let likelyRain = 60
    /// Hours shown side by side in the tab.
    nonisolated static let visibleHours = 6

    /// The first hour from `start`, within the hours shown, with rain likely.
    static func rainFrom(_ hours: [Hour], start: Int) -> Date? {
        hours.dropFirst(start).prefix(visibleHours).first { $0.rain >= likelyRain }?.date
    }

    /// The day `date` falls in, for its high and low.
    static func day(of date: Date, in days: [Day], calendar: Calendar = .current) -> Day? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// WMO weather codes to SF Symbols and words.
    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func words(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly clear"
        case 2: "Partly cloudy"
        case 3: "Cloudy"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 61...67, 80...82: "Rain"
        case 71...77, 85, 86: "Snow"
        case 95...99: "Thunderstorm"
        default: "Cloudy"
        }
    }
}

/// The open Weather tab.
struct WeatherTab: View {
    @Bindable var preferences: Preferences
    let weather: WeatherService
    @State private var picking = false
    /// The first hour the carousel shows; the carousel itself keeps it up to date as you scroll.
    @State private var firstHour: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TabHeader(title: "Weather") {
                Button { picking.toggle() } label: {
                    HStack(spacing: 4) {
                        Text(preferences.islandWeatherPlace?.name ?? "Pick a city")
                        Image(systemName: picking ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(picking ? IslandStyle.primary : IslandStyle.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(picking ? Color.white.opacity(0.1) : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            if picking || preferences.islandWeatherPlace == nil {
                PlacePicker { place in
                    preferences.islandWeatherPlace = place
                    picking = false
                    weather.clear()
                    weather.refreshIfNeeded(place: place)
                }
            } else if let report = weather.report {
                HStack(spacing: 14) {
                    Image(systemName: WeatherService.symbol(report.code, isDay: report.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 38))
                        .frame(width: 50)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(Int(report.temperature.rounded()))°")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(IslandStyle.primary)
                        Text("\(WeatherService.words(report.code)) · H \(Int(report.high.rounded()))° L \(Int(report.low.rounded()))°")
                            .font(.system(size: 12))
                            .foregroundStyle(IslandStyle.secondary)
                    }
                }
                let lastStart = max(report.hours.count - WeatherService.visibleHours, 0)
                let start = firstHour.flatMap { id in report.hours.firstIndex { $0.id == id } } ?? 0
                // A carousel of every hour ahead: swipe sideways and it glides freely, or scroll and it
                // moves an hour at a time. Above it, the day those hours are on.
                let dayDate = report.hours.indices.contains(start) ? report.hours[start].date : .now
                let dayLabel = Self.dayLabel(dayDate, day: WeatherService.day(of: dayDate, in: report.days))
                Text(dayLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IslandStyle.secondary)
                    .id(dayLabel)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.18), value: dayLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 4) {
                        ForEach(Array(report.hours.enumerated()), id: \.element.id) { index, hour in
                            let isNow = index == 0
                            VStack(spacing: 6) {
                                Text(Self.hourLabel(hour.date, isNow: isNow))
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                    .fixedSize()
                                    .foregroundStyle(isNow ? IslandStyle.volt : IslandStyle.secondary)
                                Image(systemName: WeatherService.symbol(hour.code))
                                    .symbolRenderingMode(.multicolor)
                                    .font(.system(size: 14))
                                    .frame(height: 18)
                                Text("\(Int(hour.temperature.rounded()))°")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(IslandStyle.primary)
                            }
                            .padding(.vertical, 8)
                            .containerRelativeFrame(.horizontal, count: WeatherService.visibleHours, spacing: 4)
                            .background(isNow ? IslandStyle.volt.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .scrollTargetLayout()
                }
                // A sideways scroll view takes all the height it's offered; the hours are this tall.
                .frame(height: Self.carouselHeight)
                .scrollPosition(id: $firstHour, anchor: .leading)
                .onScrollStep { steps in
                    let target = min(max(start + steps, 0), lastStart)
                    guard report.hours.indices.contains(target) else { return }
                    withAnimation(.spring(duration: 0.35, bounce: 0)) { firstHour = report.hours[target].id }
                }
                // About the hours from now, whatever the carousel shows, so the tab never changes height
                // while you scroll.
                if let rain = report.rainFrom {
                    HStack(spacing: 6) {
                        Image(systemName: "umbrella.fill")
                        Text("Rain likely \(Calendar.current.isDateInToday(rain) ? "" : rain.formatted(.dateTime.weekday(.abbreviated)) + " ")from \(rain.formatted(date: .omitted, time: .shortened))")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 0.62, green: 0.76, blue: 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.4, green: 0.55, blue: 1).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            } else {
                Text(weather.failed ? "Couldn't reach the weather service" : "Loading…")
                    .font(.system(size: 13))
                    .foregroundStyle(IslandStyle.secondary)
                    .padding(.vertical, 12)
            }
        }
        .onAppear {
            firstHour = nil
            weather.refreshIfNeeded(place: preferences.islandWeatherPlace)
        }
    }

    /// Label, icon and temperature with their padding.
    static let carouselHeight: CGFloat = 76

    /// "Now", then the hour.
    static func hourLabel(_ date: Date, isNow: Bool) -> String {
        isNow ? "Now" : date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)))
    }

    /// "Today · H 27° L 18°", "Tomorrow · …", "Wednesday · …": the day the hours you're looking at
    /// start on, above them.
    static func dayLabel(_ date: Date, day: WeatherService.Day?) -> String {
        let calendar = Calendar.current
        let name = calendar.isDateInToday(date) ? "Today" : calendar.isDateInTomorrow(date)
            ? "Tomorrow" : date.formatted(.dateTime.weekday(.wide))
        // Today's high and low are already in the line above.
        guard let day, !calendar.isDateInToday(date) else { return name }
        return "\(name) · H \(Int(day.high.rounded()))° L \(Int(day.low.rounded()))°"
    }
}

/// Type a city, pick it from the matches ("Cascavel · Paraná, Brazil").
struct PlacePicker: View {
    let pick: (WeatherPlace) -> Void
    @State private var query = ""
    @State private var results: [WeatherPlace] = []
    @State private var searching = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium))
                TextField("Search a city", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit { if let first = results.first { pick(first) } }
                if searching { ProgressView().controlSize(.mini) }
            }
            .foregroundStyle(IslandStyle.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            ForEach(results) { place in
                Button { pick(place) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(IslandStyle.tertiary)
                        Text(place.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandStyle.primary)
                        Text(place.region).font(.system(size: 12)).foregroundStyle(IslandStyle.secondary).lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("Only the city name is sent to Open-Meteo, never your location.")
                .font(.system(size: 11))
                .foregroundStyle(IslandStyle.tertiary)
                .padding(.top, 2)
        }
        .onAppear { focused = true }
        .task(id: query) {
            // Waits for a pause in typing, so it asks once per word, not per key.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            searching = true
            let found = await WeatherService.search(query)
            guard !Task.isCancelled else { return }
            results = found
            searching = false
        }
    }
}
