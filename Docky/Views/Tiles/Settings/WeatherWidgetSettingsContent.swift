//
//  WeatherWidgetSettingsContent.swift
//  Docky
//

import CoreLocation
import MapKit
import SwiftUI

struct WeatherWidgetSettingsContent: View {
    let tileID: String

    /// Mirrors the persisted selection so the header updates immediately without waiting on the tile store re-materialize.
    @State private var configuredName: String?
    @State private var isConfigured = false

    @State private var query = ""
    @State private var results: [WeatherLocationSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    @State private var unitSelection: WeatherTemperatureUnitSelection = .automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            currentLocationSection
            searchSection
            resultsSection
            Divider()
            temperatureUnitSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { loadCurrentSelection() }
        .onDisappear { searchTask?.cancel() }
    }

    private var temperatureUnitSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Temperature")
                .font(.headline)

            Picker("", selection: $unitSelection) {
                Text("Automatic").tag(WeatherTemperatureUnitSelection.automatic)
                Text("°C").tag(WeatherTemperatureUnitSelection.celsius)
                Text("°F").tag(WeatherTemperatureUnitSelection.fahrenheit)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .onChange(of: unitSelection) { _, newValue in
                applyTemperatureUnit(newValue)
            }

            Text("Automatic follows your system region.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var currentLocationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Location")
                .font(.headline)

            HStack(spacing: 8) {
                Image(systemName: isConfigured ? "mappin.circle.fill" : "location.fill")
                    .foregroundStyle(.secondary)

                Text(currentLocationDisplayName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                if isConfigured {
                    Button("Use Current Location") { useCurrentLocation() }
                        .buttonStyle(.link)
                }
            }

            Text("Pin this widget to a city, or use the device's current location.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var searchSection: some View {
        TextField("Search for a city", text: $query)
            .textFieldStyle(.roundedBorder)
            .onChange(of: query) { _, newValue in
                scheduleSearch(for: newValue)
            }
            .onSubmit {
                scheduleSearch(for: query, immediate: true)
            }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if isSearching {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Searching…").foregroundStyle(.secondary)
            }
        } else if !results.isEmpty {
            VStack(spacing: 0) {
                ForEach(results) { result in
                    Button { select(result) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.circle")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(result.name)
                                    .foregroundStyle(.primary)
                                if let subtitle = result.subtitle, !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)

                    if result.id != results.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }

    private var currentLocationDisplayName: String {
        if isConfigured {
            return configuredName ?? "Custom Location"
        }
        return "Current Location"
    }

    private func loadCurrentSelection() {
        let settings = TileStore.shared.widgetSettings(tileID: tileID) ?? [:]
        isConfigured = WeatherWidgetSettingsKey.configuredLocation(from: settings) != nil
        configuredName = settings.string(WeatherWidgetSettingsKey.locationName)
        unitSelection = WeatherWidgetSettingsKey.temperatureUnitSelection(from: settings)
    }

    private func applyTemperatureUnit(_ selection: WeatherTemperatureUnitSelection) {
        TileStore.shared.setWidgetSetting(
            tileID: tileID,
            key: WeatherWidgetSettingsKey.temperatureUnit,
            value: selection == .automatic ? nil : .string(selection.rawValue)
        )
    }

    private func scheduleSearch(for text: String, immediate: Bool = false) {
        searchTask?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            if Task.isCancelled { return }

            let found = await WeatherLocationSearch.search(query: trimmed)
            if Task.isCancelled { return }

            await MainActor.run {
                results = found
                isSearching = false
            }
        }
    }

    private func select(_ result: WeatherLocationSearchResult) {
        // Merge into existing settings so the temperature-unit override survives a location change.
        var settings = TileStore.shared.widgetSettings(tileID: tileID) ?? [:]
        settings[WeatherWidgetSettingsKey.locationName] = .string(result.name)
        settings[WeatherWidgetSettingsKey.latitude] = .number(result.latitude)
        settings[WeatherWidgetSettingsKey.longitude] = .number(result.longitude)
        TileStore.shared.setWidgetSettings(tileID: tileID, settings: settings)

        isConfigured = true
        configuredName = result.name
        query = ""
        results = []
        searchTask?.cancel()
    }

    private func useCurrentLocation() {
        // Drop only the location keys; keep the temperature-unit override.
        var settings = TileStore.shared.widgetSettings(tileID: tileID) ?? [:]
        settings.removeValue(forKey: WeatherWidgetSettingsKey.locationName)
        settings.removeValue(forKey: WeatherWidgetSettingsKey.latitude)
        settings.removeValue(forKey: WeatherWidgetSettingsKey.longitude)
        TileStore.shared.setWidgetSettings(tileID: tileID, settings: settings)

        isConfigured = false
        configuredName = nil
        query = ""
        results = []
        searchTask?.cancel()
    }
}

struct WeatherLocationSearchResult: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String?
    let latitude: Double
    let longitude: Double
}

enum WeatherLocationSearch {
    static func search(query: String) async -> [WeatherLocationSearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]

        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start() else {
            return []
        }

        return response.mapItems.prefix(8).compactMap { item in
            let coordinate = item.location.coordinate
            let addresses = item.addressRepresentations
            let name = addresses?.cityName ?? item.name ?? item.address?.shortAddress ?? "Location"
            let context = addresses?.cityWithContext(.full)
            let subtitle = context == name ? nil : context

            return WeatherLocationSearchResult(
                name: name,
                subtitle: subtitle,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
    }
}
