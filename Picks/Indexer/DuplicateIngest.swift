import Foundation

public enum DuplicateIngest: Sendable {
    /// Relative paths marked DUP in `_duplicate_report/true_content_duplicates.csv`.
    public static func dupPaths(eventRoot: URL) -> Set<String> {
        let csv = eventRoot
            .appendingPathComponent("_duplicate_report")
            .appendingPathComponent("true_content_duplicates.csv")
        guard FileManager.default.isReadableFile(atPath: csv.path) else { return [] }
        guard let text = try? String(contentsOf: csv, encoding: .utf8) else { return [] }
        var dups: Set<String> = []
        for (i, line) in text.split(whereSeparator: \.isNewline).enumerated() {
            if i == 0 { continue }
            let cols = parseCSVLine(String(line))
            guard cols.count >= 5 else { continue }
            let role = cols[3].trimmingCharacters(in: .whitespaces).uppercased()
            var path = cols[4].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            path = path.replacingOccurrences(of: "\"\"", with: "\"")
            if role == "DUP" {
                dups.insert(path)
            }
        }
        return dups
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var cols: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == ",", !inQuotes {
                cols.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        cols.append(current)
        return cols
    }
}
