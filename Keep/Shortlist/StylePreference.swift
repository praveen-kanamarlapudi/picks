import Foundation

/// Candid sorts first alphabetically. We always prefer Traditional when both exist.
public enum StylePreference: Sendable {
    public static func isTraditional(_ name: String) -> Bool {
        name.localizedCaseInsensitiveContains("traditional")
    }

    public static func isCandid(_ name: String) -> Bool {
        name.localizedCaseInsensitiveContains("candid")
    }

    public static func styleRank(_ style: String) -> Int {
        if isTraditional(style) { return 0 }
        if isCandid(style) { return 2 }
        return 1
    }

    public static func sortedStyles(_ styles: [String]) -> [String] {
        styles.sorted { a, b in
            let ra = styleRank(a)
            let rb = styleRank(b)
            if ra != rb { return ra < rb }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    public static func defaultStyle(in styles: [String]) -> String {
        styles.first(where: isTraditional) ?? styles.first ?? ""
    }

    /// Keep the last ceremony unless it is the Candid pile. Then pick Traditional.
    public static func defaultCeremony(session: String, all: [String]) -> String {
        if all.contains(session), !isCandid(session) { return session }
        if let traditional = all.first(where: isTraditional) { return traditional }
        if all.contains(session) { return session }
        return all.first ?? ""
    }
}
