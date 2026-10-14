import Foundation
import MapKit

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
