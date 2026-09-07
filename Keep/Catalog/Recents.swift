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
    private static let key = "keep.recents.v1"

    public static func load() -> [RecentEvent] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([RecentEvent].self, from: data) else {
            return []
        }
        return items.sorted { $0.lastOpened > $1.lastOpened }
    }

    public static func remember(id: String, name: String) {
        var items = load().filter { $0.id != id }
        items.insert(RecentEvent(id: id, name: name), at: 0)
        if items.count > 12 { items = Array(items.prefix(12)) }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
