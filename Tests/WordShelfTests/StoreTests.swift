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
        XCTAssertEqual(try store.exportCSV(), "已查单词,中文含义\r\n")
        try store.save("Apple"); try store.save("apple"); try store.save("don't")
        let csv = try store.exportCSV()
        let rows = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(rows.first, "已查单词,中文含义")
        XCTAssertEqual(rows.last, "")
        XCTAssertEqual(Set(rows.dropFirst().dropLast()), ["\"apple\",\"\"", "\"don't\",\"\""])
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
        XCTAssertEqual(try reopened.exportCSV(), "已查单词,中文含义\r\n\"apple\",\"苹果, \"\"水果\"\"\n第二行\"\r\n")
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
        XCTAssertEqual(try reopened.exportCSV(), "已查单词,中文含义\r\n")
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
}
