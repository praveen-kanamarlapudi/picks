import Foundation

public struct RecentEvent: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var lastOpened: Date

    public init(id: String, name: String, lastOpened: Date = Date()) {
        self.id = id
        self.name = name
        self.lastOpened = lastOpened
    }
}

public enum RecentsStore {
    private static let key = "picks.recents.v1"
    private static let legacyKey = "keep.recents.v1"
    private static let legacySuite = "app.keep.mac"

    public static func load() -> [RecentEvent] {
        if let items = decode(UserDefaults.standard.data(forKey: key)), !items.isEmpty {
            return sorted(items)
        }
        let inherited = decode(UserDefaults.standard.data(forKey: legacyKey))
            ?? decode(UserDefaults(suiteName: legacySuite)?.data(forKey: legacyKey))
            ?? []
        if !inherited.isEmpty, let data = try? JSONEncoder().encode(inherited) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return sorted(inherited)
    }

    public static func remember(id: String, name: String) {
        var items = load().filter { $0.id != id }
        items.insert(RecentEvent(id: id, name: name), at: 0)
        if items.count > 12 { items = Array(items.prefix(12)) }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func decode(_ data: Data?) -> [RecentEvent]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([RecentEvent].self, from: data)
    }

    private static func sorted(_ items: [RecentEvent]) -> [RecentEvent] {
        items.sorted { $0.lastOpened > $1.lastOpened }
    }
}
