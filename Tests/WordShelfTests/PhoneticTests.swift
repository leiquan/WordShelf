import XCTest
import CSQLite
@testable import WordShelf

final class PhoneticTests: XCTestCase {
    func testResponseFallbackAndMissingPhonetic() throws {
        let data = Data(#"[{"hwi":{"hw":"ap*ple","prs":[{"ipa":"ˈæpəl"}]}}]"#.utf8)
        XCTAssertEqual(try PhoneticService.parse(data, word: "apple"), "/ˈæpəl/")
        XCTAssertNil(try PhoneticService.parse(data, word: "apply"))
        XCTAssertNil(try PhoneticService.parse(Data(#"[{"hwi":{"hw":"ap*ple","prs":[{"mw":"a-pəl"}]}}]"#.utf8), word: "apple"))
        XCTAssertNil(try PhoneticService.parse(Data(#"["apply","apples"]"#.utf8), word: "apple"))
        XCTAssertNil(try PhoneticService.parse(data, word: "apples"))
        let plural = Data(#"[{"hwi":{"hw":"ap*ple","prs":[{"ipa":"ˈæpəl"}]},"ins":[{"if":"ap*ples","prs":[{"ipa":"ˈæpəlz"}]}]}]"#.utf8)
        XCTAssertEqual(try PhoneticService.parse(plural, word: "apples"), "/ˈæpəlz/")
        XCTAssertThrowsError(try PhoneticService.parse(Data(#"{"error":"unavailable"}"#.utf8), word: "apple"))
    }
    func testLegacyDatabaseMigrationAndPersistentCacheExportsPhonetic() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("words.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        let sql = "CREATE TABLE words(word TEXT PRIMARY KEY,count INTEGER NOT NULL,first REAL NOT NULL,last REAL NOT NULL,source TEXT NOT NULL,meaning TEXT NOT NULL DEFAULT ''); INSERT INTO words VALUES('apple',1,1000,1000,'Look Up','苹果');"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        var store: Store? = try Store(url: url)
        XCTAssertEqual(try store!.all().first?.phonetic, "")
        try store!.setPhonetic("apple", value: "/ˈæpəl/")
        store = nil
        let reopened = try Store(url: url)
        let word = try XCTUnwrap(reopened.all().first)
        XCTAssertEqual(word.phonetic, "/ˈæpəl/")
        XCTAssertEqual(word.meaning, "苹果")
        XCTAssertEqual(word.firstSavedAt, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(try reopened.exportCSV(), "单词,音标,中文含义\r\n\"apple\",\"/ˈæpəl/\",\"苹果\"\r\n")
        try reopened.delete("apple")
        try reopened.setPhonetic("apple", value: "/late/")
        XCTAssertTrue(try reopened.all().isEmpty)
    }
    func testLiveServiceReturnsApplePhonetic() async throws {
        guard ProcessInfo.processInfo.environment["WORDSHELF_LIVE_API_TEST"] == "1" else {
            throw XCTSkip("Run explicitly to verify the live dictionary service")
        }
        guard let key = ProcessInfo.processInfo.environment["WORDSHELF_MW_TEST_KEY"], !key.isEmpty else { throw XCTSkip("Requires a personal Learner’s API key") }
        let service = PhoneticService(apiKey: key)
        let result = await service.lookup("apple", retry: true)
        guard case .found(let text) = result else { return XCTFail("Live service did not return apple phonetic") }
        XCTAssertFalse(text.isEmpty)
        let cached = await service.lookup("apple")
        guard case .found(let cachedText) = cached else { return XCTFail("Memory cache missing") }
        XCTAssertEqual(cachedText, text)
    }
    func testRetryQueueSkipsCachedWordsAndRotatesMissingWords() {
        let date = Date(timeIntervalSince1970: 1000)
        let apple = Word(text: "apple", meaning: "", firstSavedAt: date)
        let pear = Word(text: "pear", meaning: "", firstSavedAt: date.addingTimeInterval(1))
        let cached = Word(text: "cached", meaning: "", firstSavedAt: date.addingTimeInterval(2), phonetic: "/cached/")
        let words = [apple, pear, cached]
        XCTAssertEqual(PhoneticQueue.next(in: words, attempts: [:])?.text, "pear")
        XCTAssertEqual(PhoneticQueue.next(in: words, attempts: ["pear": date])?.text, "apple")
        XCTAssertEqual(PhoneticQueue.next(in: words, attempts: ["pear": date, "apple": date.addingTimeInterval(5)])?.text, "pear")
        XCTAssertNil(PhoneticQueue.next(in: [cached], attempts: [:]))
        XCTAssertNil(PhoneticQueue.next(in: [], attempts: [:]))
    }
    func testPersonalQuotaIsPersistentPerKeyAndExpires() {
        let name = "wordshelf-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertNil(APIQuota.reserve(key: "test-a", defaults: defaults, now: now, limit: 2))
        XCTAssertNil(APIQuota.reserve(key: "test-a", defaults: defaults, now: now, limit: 2))
        XCTAssertEqual(APIQuota.reserve(key: "test-a", defaults: defaults, now: now, limit: 2), now.addingTimeInterval(86400))
        XCTAssertNil(APIQuota.reserve(key: "test-b", defaults: defaults, now: now, limit: 2))
        XCTAssertNil(APIQuota.reserve(key: "test-a", defaults: defaults, now: now.addingTimeInterval(86400), limit: 2))
    }
    func testOldProviderCacheIsNotPresentedAsMerriamWebsterIPA() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("words.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        let sql = "CREATE TABLE words(word TEXT PRIMARY KEY,count INTEGER NOT NULL,first REAL NOT NULL,last REAL NOT NULL,source TEXT NOT NULL,meaning TEXT NOT NULL DEFAULT '',phonetic TEXT NOT NULL DEFAULT ''); INSERT INTO words VALUES('apple',1,1000,1000,'Look Up','苹果','/old/');"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let store = try Store(url: url)
        XCTAssertEqual(try store.all().first?.phonetic, "")
        XCTAssertEqual(try store.all().first?.meaning, "苹果")
        try store.setPhonetic("apple", value: "/ˈæpəl/")
        XCTAssertEqual(try store.all().first?.phonetic, "/ˈæpəl/")
    }
}
