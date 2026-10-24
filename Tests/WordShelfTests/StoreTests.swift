import XCTest
@testable import WordShelf
final class StoreTests: XCTestCase {
    func testOnlyExplicitLookupMenuTitles() {
        XCTAssertEqual(LookupTitle.word("Look Up “Apple”"), "apple")
        XCTAssertEqual(LookupTitle.word("查询“don't”"), "don't")
        XCTAssertEqual(LookupTitle.word("Look Up \"mother-in-law\""), "mother-in-law")
        for title in ["Copy “apple”", "Look Up", "Look Up apple", "Look Up “two words”", "查询“你好”", "Look Up “apple” in browser", "Look Up “123”"] { XCTAssertNil(LookupTitle.word(title), title) }
    }
    func testClickMustFinishInsideSameItem() {
        let click = MenuClick(word: "apple", bounds: CGRect(x: 100, y: 100, width: 100, height: 20), timestamp: 1)
        XCTAssertEqual(click.released(at: CGPoint(x: 110, y: 110), timestamp: 2), "apple")
        XCTAssertNil(click.released(at: CGPoint(x: 90, y: 110), timestamp: 2))
        XCTAssertNil(click.released(at: CGPoint(x: 110, y: 110), timestamp: 12))
        XCTAssertNil(click.released(at: CGPoint(x: 110, y: 110), timestamp: 0))
    }
    func testCSVExportContainsUniqueWordsAndDoesNotChangeList() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try Store(url: folder.appendingPathComponent("words.sqlite"))
        XCTAssertEqual(try store.exportCSV(), "单词,音标,中文含义\r\n")
        try store.save("Apple"); try store.save("apple"); try store.save("don't")
        let csv = try store.exportCSV()
        let rows = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(rows.first, "单词,音标,中文含义")
        XCTAssertEqual(rows.last, "")
        XCTAssertEqual(Set(rows.dropFirst().dropLast()), ["\"apple\",\"\",\"\"", "\"don't\",\"\",\"\""])
        XCTAssertEqual(try store.all().count, 2)
    }
    func testManualMeaningPersistsUpdatesClearsAndExports() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("words.sqlite")
        var store: Store? = try Store(url: url)
        try store!.save("apple")
        try store!.setMeaning("apple", value: "苹果")
        store = nil
        let reopened = try Store(url: url)
        XCTAssertEqual(try reopened.all().first?.meaning, "苹果")
        let value = "苹果, \"水果\"\n第二行"
        try reopened.setMeaning("apple", value: value)
        try reopened.save("APPLE")
        XCTAssertEqual(try reopened.all().count, 1)
        XCTAssertEqual(try reopened.all().first?.meaning, value)
        XCTAssertEqual(try reopened.exportCSV(), "单词,音标,中文含义\r\n\"apple\",\"\",\"苹果, \"\"水果\"\"\n第二行\"\r\n")
        try reopened.setMeaning("apple", value: "")
        XCTAssertEqual(try reopened.all().first?.meaning, "")
    }
    func testClearAllPersistsAndAllowsCollectionAgain() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("words.sqlite")
        var store: Store? = try Store(url: url)
        try store!.save("apple"); try store!.setMeaning("apple", value: "苹果")
        try store!.save("pear"); try store!.clearAll(); store = nil
        let reopened = try Store(url: url)
        XCTAssertTrue(try reopened.all().isEmpty)
        XCTAssertEqual(try reopened.exportCSV(), "单词,音标,中文含义\r\n")
        try reopened.save("apple")
        XCTAssertEqual(try reopened.all().count, 1)
        XCTAssertEqual(try reopened.all().first?.meaning, "")
    }
    func testPersistentUniqueList() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("words.sqlite")
        var store: Store? = try Store(url: url)
        try store!.save("Apple"); try store!.save("apple"); try store!.save("pear")
        store = nil
        let reopened = try Store(url: url)
        XCTAssertEqual(Set(try reopened.all().map(\.text)), ["apple", "pear"])
        XCTAssertThrowsError(try reopened.save("two words"))
        XCTAssertEqual(try reopened.all().count, 2)
    }

    func testDateGroupingUsesLocalDaysAndNewestFirst() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let boundary = calendar.date(from: DateComponents(year: 2024, month: 10, day: 24))!
        let words = [
            Word(text: "apple", meaning: "苹果", firstSavedAt: boundary.addingTimeInterval(-1)),
            Word(text: "pear", meaning: "", firstSavedAt: boundary),
            Word(text: "banana", meaning: "", firstSavedAt: boundary.addingTimeInterval(1))
        ]
        let groups = WordDay.groups(words, calendar: calendar)
        XCTAssertEqual(groups.map { $0.words.count }, [2, 1])
        XCTAssertEqual(groups[0].words.map(\.text), ["banana", "pear"])
        XCTAssertEqual(groups[1].words.first?.meaning, "苹果")
        XCTAssertTrue(WordDay.groups([], calendar: calendar).isEmpty)
    }
    func testFirstDateSurvivesDuplicateAndReopen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("words.sqlite")
        let first = Date(timeIntervalSince1970: 1000)
        var store: Store? = try Store(url: url)
        try store!.save("apple", at: first)
        try store!.save("APPLE", at: first.addingTimeInterval(86400))
        try store!.setMeaning("apple", value: "苹果")
        store = nil
        let reopened = try Store(url: url)
        let words = try reopened.all()
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words.first?.firstSavedAt, first)
        XCTAssertEqual(words.first?.meaning, "苹果")
        XCTAssertEqual(WordDay.groups(words).count, 1)
    }

    func testDeleteOnlySelectedWordPersistsAndUpdatesGroupsAndCSV() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("words.sqlite")
        var store: Store? = try Store(url: url)
        try store!.save("apple", at: Date(timeIntervalSince1970: 1000))
        try store!.setMeaning("apple", value: "苹果")
        try store!.save("pear", at: Date(timeIntervalSince1970: 200000))
        try store!.setMeaning("pear", value: "梨")
        try store!.delete("apple")
        store = nil
        let reopened = try Store(url: url)
        let words = try reopened.all()
        XCTAssertEqual(words.map(\.text), ["pear"])
        XCTAssertEqual(words.first?.meaning, "梨")
        XCTAssertEqual(WordDay.groups(words).map { $0.words.count }, [1])
        XCTAssertEqual(try reopened.exportCSV(), "单词,音标,中文含义\r\n\"pear\",\"\",\"梨\"\r\n")
        try reopened.delete("pear")
        XCTAssertTrue(WordDay.groups(try reopened.all()).isEmpty)
        try reopened.save("apple")
        XCTAssertEqual(try reopened.all().first?.meaning, "")
    }
}
