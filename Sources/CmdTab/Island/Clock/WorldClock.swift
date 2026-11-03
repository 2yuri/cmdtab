import AppKit
import Foundation
import Observation
import SwiftUI

/// A city on the world clock.
struct WorldCity: Codable, Hashable, Identifiable {
    var timeZoneID: String
    var name: String

    var id: String { timeZoneID }
    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    static var local: WorldCity {
        let id = TimeZone.current.identifier
        return WorldCity(timeZoneID: id, name: cityName(of: id))
    }

    /// "America/Sao_Paulo" → "Sao Paulo".
    static func cityName(of identifier: String) -> String {
        (identifier.split(separator: "/").last.map(String.init) ?? identifier).replacingOccurrences(of: "_", with: " ")
    }

    /// Cities whose name or region matches `query`, for "Add city".
    static func search(_ query: String, limit: Int = 6) -> [WorldCity] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { return [] }
        return TimeZone.knownTimeZoneIdentifiers
            .filter { $0.contains("/") && !$0.hasPrefix("Etc/") }
            .map { WorldCity(timeZoneID: $0, name: cityName(of: $0)) }
            .filter { $0.name.localizedCaseInsensitiveContains(query) || $0.timeZoneID.localizedCaseInsensitiveContains(query) }
            .sorted { lhs, rhs in
                let lhsPrefix = lhs.name.lowercased().hasPrefix(query.lowercased())
                let rhsPrefix = rhs.name.lowercased().hasPrefix(query.lowercased())
                return lhsPrefix != rhsPrefix ? lhsPrefix : lhs.name < rhs.name
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Three letters for the header: "SAO", "LIS".
    var short: String {
        String(name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "").prefix(3)).uppercased()
    }

    func time(at date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }

    /// "Here", "+3 h", "−2 h · Tue".
    func offsetText(at date: Date, from here: TimeZone = .current) -> String {
        let seconds = timeZone.secondsFromGMT(for: date) - here.secondsFromGMT(for: date)
        var text: String
        if seconds == 0 {
            text = "Here"
        } else {
            let hours = Double(seconds) / 3600
            let value = hours == hours.rounded() ? String(Int(abs(hours))) : String(format: "%.1f", abs(hours))
            text = "\(seconds > 0 ? "+" : "−")\(value) h"
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var hereCalendar = Calendar(identifier: .gregorian)
        hereCalendar.timeZone = here
        if calendar.component(.day, from: date) != hereCalendar.component(.day, from: date) {
            text += " · " + date.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated))
        }
        return text
    }

    func isDaytime(at date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        return (7..<19).contains(hour)
    }
}

/// The open Clock tab: every city.
struct ClockTab: View {
    @Bindable var preferences: Preferences
    @State private var adding = false
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabHeader(title: "World clock") {
                Button { adding.toggle(); query = "" } label: {
                    Label(adding ? "Done" : "Add city", systemImage: adding ? "checkmark" : "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(IslandStyle.volt)
                }
                .buttonStyle(.plain)
            }
            if adding {
                AddCity(query: $query) { city in
                    if !preferences.islandCities.contains(city) { preferences.islandCities.append(city) }
                    adding = false
                    query = ""
                }
            }
            TimelineView(.everyMinute) { context in
                VStack(spacing: 4) {
                    ForEach(preferences.islandCities) { city in
                        CityRow(city: city, date: context.date) {
                            preferences.islandCities.removeAll { $0 == city }
                        }
                    }
                }
            }
        }
    }
}

private struct CityRow: View {
    let city: WorldCity
    let date: Date
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        let day = city.isDaytime(at: date)
        HStack(spacing: 10) {
            Image(systemName: day ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 12))
                .foregroundStyle(day ? IslandStyle.amber : Color(red: 0.6, green: 0.55, blue: 1))
                .frame(width: 28, height: 28)
                .background((day ? IslandStyle.amber : Color(red: 0.6, green: 0.55, blue: 1)).opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(city.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandStyle.primary)
                Text(city.offsetText(at: date)).font(.system(size: 11)).foregroundStyle(IslandStyle.secondary)
            }
            Spacer()
            if hovering && city.timeZoneID != TimeZone.current.identifier {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(IslandStyle.secondary)
                }
                .buttonStyle(.plain)
            }
            Text(city.time(at: date))
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(IslandStyle.primary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct AddCity: View {
    @Binding var query: String
    let pick: (WorldCity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField("City", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            ForEach(WorldCity.search(query)) { city in
                Button { pick(city) } label: {
                    HStack {
                        Text(city.name).foregroundStyle(IslandStyle.primary)
                        Spacer()
                        Text(city.timeZoneID).foregroundStyle(IslandStyle.tertiary)
                    }
                    .font(.system(size: 12))
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
