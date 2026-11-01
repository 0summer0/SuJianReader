import SwiftUI

struct ReadingPlace: Codable, Equatable {
    var anchor: String?
    var delta: Double
    var offsetY: Double
    var contentHeight: Double

    static func parse(_ value: Any?) -> ReadingPlace? {
        guard let raw = value as? [String: Any] else { return nil }
        let offsetY = (raw["y"] as? NSNumber)?.doubleValue ?? 0
        let height = (raw["height"] as? NSNumber)?.doubleValue ?? 0
        let delta = (raw["delta"] as? NSNumber)?.doubleValue ?? 0
        let anchor = raw["anchor"] as? String
        let token = (anchor?.isEmpty == false) ? anchor : nil
        guard offsetY >= 0 else { return nil }
        if offsetY <= 24 {
            return ReadingPlace(anchor: nil, delta: 0, offsetY: 0, contentHeight: height)
        }
        return ReadingPlace(anchor: token, delta: delta, offsetY: offsetY, contentHeight: height)
    }
}

final class ReadingPlaceStore {
    static let shared = ReadingPlaceStore()

    private var places: [UUID: ReadingPlace] = [:]
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("reading-places.json")
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([String: ReadingPlace].self, from: data) else { return }
        for (key, place) in stored {
            if let id = UUID(uuidString: key) {
                places[id] = place
            }
        }
    }

    func place(for id: UUID) -> ReadingPlace? {
        places[id]
    }

    func save(_ place: ReadingPlace, for id: UUID) {
        #if DEBUG

        if ProcessInfo.processInfo.arguments.contains("-readerUITestFixture") { return }
        #endif
        places[id] = place
        let stored = Dictionary(uniqueKeysWithValues: places.map { ($0.key.uuidString, $0.value) })
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

private struct ReadingPlacesKey: EnvironmentKey {
    static let defaultValue = ReadingPlaceStore.shared
}

extension EnvironmentValues {
    var readingPlaces: ReadingPlaceStore {
        get { self[ReadingPlacesKey.self] }
        set { self[ReadingPlacesKey.self] = newValue }
    }
}
