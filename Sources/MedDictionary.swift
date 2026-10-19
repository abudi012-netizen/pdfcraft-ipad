import Foundation
import SQLite3

struct MedEntry: Identifiable, Hashable {
    let id: Int64
    let name: String
    let category: String
    let definition: String
    let actions: String
    let synonyms: String
}

/// Offline medical dictionary built from NLM MeSH (bundled as MedDict.sqlite).
final class MedDictionary {
    static let shared = MedDictionary()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "meddict")

    var isAvailable: Bool { db != nil }

    private init() {
        guard let url = Bundle.main.url(forResource: "MedDict", withExtension: "sqlite") else { return }
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) != SQLITE_OK {
            db = nil
        }
    }

    /// Exact matches first (also tries simple plural forms), then words starting with the query.
    func lookup(_ raw: String, limit: Int = 30) -> (exact: [MedEntry], suggestions: [MedEntry]) {
        queue.sync {
            let q = Self.normalize(raw)
            guard db != nil, !q.isEmpty else { return ([], []) }

            var candidates = [q]
            if q.hasSuffix("ies") { candidates.append(String(q.dropLast(3)) + "y") }
            if q.hasSuffix("es") { candidates.append(String(q.dropLast(2))) }
            if q.hasSuffix("s") { candidates.append(String(q.dropLast())) }

            var exact: [MedEntry] = []
            for c in candidates where exact.isEmpty {
                exact = fetch("""
                    SELECT DISTINCT e.id, e.name, e.category, e.definition, e.actions, e.synonyms
                    FROM terms t JOIN entries e ON e.id = t.entry_id
                    WHERE t.term = ? LIMIT 10
                    """, [c])
            }
            let exactIDs = Set(exact.map(\.id))
            let suggestions = fetch("""
                SELECT DISTINCT e.id, e.name, e.category, e.definition, e.actions, e.synonyms
                FROM terms t JOIN entries e ON e.id = t.entry_id
                WHERE t.term >= ? AND t.term < ? ORDER BY length(t.term) LIMIT ?
                """, [q, q + "\u{FFFF}", String(limit)])
                .filter { !exactIDs.contains($0.id) }
            return (exact, suggestions)
        }
    }

    static func normalize(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    private func fetch(_ sql: String, _ args: [String]) -> [MedEntry] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, arg) in args.enumerated() {
            if let n = Int64(arg), sql.contains("LIMIT ?"), i == args.count - 1 {
                sqlite3_bind_int64(stmt, Int32(i + 1), n)
            } else {
                sqlite3_bind_text(stmt, Int32(i + 1), arg, -1, transient)
            }
        }
        var out: [MedEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func col(_ i: Int32) -> String {
                guard let c = sqlite3_column_text(stmt, i) else { return "" }
                return String(cString: c)
            }
            out.append(MedEntry(id: sqlite3_column_int64(stmt, 0), name: col(1), category: col(2),
                                definition: col(3), actions: col(4), synonyms: col(5)))
        }
        return out
    }
}
