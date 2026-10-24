import Foundation
import CSQLite

struct Word: Identifiable {
    var id: String { text }
    let text: String
    let meaning: String
    let firstSavedAt: Date
    var phonetic: String = ""
}
struct WordDay: Identifiable {
    var id: Date { date }
    let date: Date
    let words: [Word]
    static func groups(_ words: [Word], calendar: Calendar = .autoupdatingCurrent) -> [WordDay] {
        Dictionary(grouping: words, by: { calendar.startOfDay(for: $0.firstSavedAt) })
            .map { WordDay(date: $0.key, words: $0.value.sorted {
                if $0.firstSavedAt == $1.firstSavedAt { return $0.text < $1.text }
                return $0.firstSavedAt > $1.firstSavedAt
            }) }
            .sorted { $0.date > $1.date }
    }
}
enum WordRules {
    static func normalize(_ input: String) -> String? {
        let word = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "’", with: "'").lowercased()
        guard word.count <= 80, word.range(of: "^[a-z]+(?:['-][a-z]+)*$", options: .regularExpression) != nil else { return nil }
        return word
    }
}
final class Store {
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw failure() }
        // Preserve compatibility with previously collected words; no destructive migration.
        guard sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS words(word TEXT PRIMARY KEY,count INTEGER NOT NULL,first REAL NOT NULL,last REAL NOT NULL,source TEXT NOT NULL,meaning TEXT NOT NULL DEFAULT '')", nil, nil, nil) == SQLITE_OK else { throw failure() }
        var schema: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(words)", -1, &schema, nil) == SQLITE_OK else { throw failure() }
        var hasPhonetic = false
        var hasProvider = false
        while sqlite3_step(schema) == SQLITE_ROW {
            if let name = sqlite3_column_text(schema, 1) {
                let column = String(cString: name)
                if column == "phonetic" { hasPhonetic = true }
                if column == "phonetic_provider" { hasProvider = true }
            }
        }
        sqlite3_finalize(schema)
        if !hasPhonetic {
            guard sqlite3_exec(db, "ALTER TABLE words ADD COLUMN phonetic TEXT NOT NULL DEFAULT ''", nil, nil, nil) == SQLITE_OK else { throw failure() }
        }
        if !hasProvider {
            guard sqlite3_exec(db, "ALTER TABLE words ADD COLUMN phonetic_provider TEXT NOT NULL DEFAULT ''", nil, nil, nil) == SQLITE_OK else { throw failure() }
        }
    }
    deinit { sqlite3_close(db) }
    private func failure() -> NSError { NSError(domain: "SQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: db.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开本地数据库"]) }
    func save(_ input: String, at date: Date = Date()) throws {
        guard let word = WordRules.normalize(input) else { throw NSError(domain: "WordShelf", code: 2, userInfo: [NSLocalizedDescriptionKey: "仅支持记录单个英文单词"] ) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO words(word,count,first,last,source) VALUES(?,1,?,?, 'Look Up')", -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        let now = date.timeIntervalSince1970
        sqlite3_bind_text(stmt, 1, word, -1, transient)
        sqlite3_bind_double(stmt, 2, now); sqlite3_bind_double(stmt, 3, now)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }
    func setMeaning(_ word: String, value: String) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE words SET meaning=? WHERE word=?", -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, value.trimmingCharacters(in: .whitespacesAndNewlines), -1, transient)
        sqlite3_bind_text(stmt, 2, word, -1, transient)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }
    func setPhonetic(_ word: String, value: String) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE words SET phonetic=?,phonetic_provider='merriam-webster-learners' WHERE word=?", -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, value, -1, transient)
        sqlite3_bind_text(stmt, 2, word, -1, transient)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }
    func delete(_ word: String) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM words WHERE word=?", -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, word, -1, transient)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }
    func clearAll() throws {
        guard sqlite3_exec(db, "DELETE FROM words", nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    func exportCSV() throws -> String {
        func field(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let rows = try all()
        let lines = rows.map { [field($0.text), field($0.phonetic), field($0.meaning)].joined(separator: ",") }
        return "单词,音标,中文含义\r\n" + (lines.isEmpty ? "" : lines.joined(separator: "\r\n") + "\r\n")
    }
    func all() throws -> [Word] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT word,meaning,first,CASE WHEN phonetic_provider='merriam-webster-learners' THEN phonetic ELSE '' END FROM words ORDER BY first DESC,word", -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        var rows: [Word] = []
        while true {
            let status = sqlite3_step(stmt)
            if status == SQLITE_DONE { return rows }
            guard status == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) else { throw failure() }
            rows.append(Word(text: String(cString: text), meaning: String(cString: sqlite3_column_text(stmt, 1)), firstSavedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)), phonetic: String(cString: sqlite3_column_text(stmt, 3))))
        }
    }
}
