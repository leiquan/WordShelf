import XCTest
@testable import WordShelf

private actor ReplyGate {
    private var continuations: [CheckedContinuation<PhoneticResult, Never>] = []
    private var result: PhoneticResult?
    private(set) var calls = 0
    func lookup() async -> PhoneticResult {
        calls += 1
        if let result { return result }
        return await withCheckedContinuation { continuations.append($0) }
    }
    func resolve(_ value: PhoneticResult) {
        result = value
        let waiting = continuations; continuations.removeAll()
        for continuation in waiting { continuation.resume(returning: value) }
    }
}
private actor QuotaReplies {
    private(set) var times: [Date] = []
    func lookup() -> PhoneticResult {
        times.append(Date())
        return times.count == 1 ? .quota(Date().addingTimeInterval(0.08)) : .found("/ˈæpəl/")
    }
}
final class OptimizationTests: XCTestCase {
    func testMissingAndNetworkFailuresHaveDifferentRetryWindows() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(PhoneticRetry.date(for: .missing, failures: 9, now: now), now.addingTimeInterval(7 * 86400))
        XCTAssertEqual(PhoneticRetry.date(for: .failed("offline"), failures: 0, now: now), now.addingTimeInterval(60))
        XCTAssertEqual(PhoneticRetry.date(for: .failed("offline"), failures: 1, now: now), now.addingTimeInterval(120))
        XCTAssertEqual(PhoneticRetry.date(for: .failed("offline"), failures: 100, now: now), now.addingTimeInterval(6 * 3600))
        XCTAssertNil(PhoneticRetry.date(for: .found("/a/"), failures: 0, now: now))
    }
    func testRetryWindowSurvivesReopenAndSuccessClearsIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("words.sqlite")
        let now = Date(timeIntervalSince1970: 1000)
        let until = now.addingTimeInterval(60)
        var store: Store? = try Store(url: url)
        try store!.save("apple", at: now)
        try store!.setMeaning("apple", value: "苹果")
        try store!.deferPhonetic("apple", until: until, failures: 2)
        store = nil
        let reopened = try Store(url: url)
        var words = try reopened.all()
        XCTAssertEqual(words.first?.phoneticFailures, 2)
        XCTAssertNil(PhoneticQueue.next(in: words, attempts: [:], now: now))
        XCTAssertEqual(PhoneticQueue.next(in: words, attempts: [:], now: until)?.text, "apple")
        try reopened.setPhonetic("apple", value: "/ˈæpəl/")
        words = try reopened.all()
        XCTAssertEqual(words.first?.phoneticFailures, 0)
        XCTAssertEqual(words.first?.meaning, "苹果")
        XCTAssertNil(PhoneticQueue.next(in: words, attempts: [:], now: until))
    }
    @MainActor func testUndoRestoresDraftMeaningDateAndPhoneticWithoutOverwritingRecollection() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "wordshelf-test-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let model = Model(storeURL: folder.appendingPathComponent("words.sqlite"), collectorEnabled: false, loadCredential: false, preferences: preferences)
        let date = Date(timeIntervalSince1970: 1000)
        try model.store!.save("apple", at: date)
        try model.store!.setPhonetic("apple", value: "/ˈæpəl/")
        model.reload(); model.stageMeaning("apple", value: "草稿中的苹果")
        model.deleteWord("apple")
        XCTAssertTrue(model.words.isEmpty)
        XCTAssertEqual(model.deletedWords.count, 1)
        model.undoDelete()
        XCTAssertEqual(model.words.first?.meaning, "草稿中的苹果")
        XCTAssertEqual(model.words.first?.firstSavedAt, date)
        XCTAssertEqual(model.words.first?.phonetic, "/ˈæpəl/")
        XCTAssertEqual(model.days.first?.words.count, 1)
        model.deleteWord("apple")
        try model.store!.save("apple")
        try model.store!.setMeaning("apple", value: "重新填写")
        model.reload(); model.undoDelete()
        XCTAssertEqual(model.words.first?.meaning, "重新填写")
    }
    @MainActor func testCancelAutomaticQueryClearsLoadingAndAllowsManualRetry() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "wordshelf-test-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let gate = ReplyGate()
        let model = Model(storeURL: folder.appendingPathComponent("words.sqlite"), collectorEnabled: false, loadCredential: false, preferences: preferences, phoneticLookup: { _ in await gate.lookup() })
        try model.store!.save("apple"); model.reload(); model.hasPhoneticKey = true
        model.setAutomaticPhonetics(true)
        for _ in 0..<100 {
            if await gate.calls > 0 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(model.phoneticStates["apple"], "查询中…")
        model.setAutomaticPhonetics(false)
        XCTAssertNotEqual(model.phoneticStates["apple"], "查询中…")
        await gate.resolve(.found("/ˈæpəl/"))
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(model.words.first?.phonetic, "")
        model.retryPhonetic(model.words[0])
        for _ in 0..<100 {
            if model.words.first?.phonetic.isEmpty == false { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(model.words.first?.phonetic, "/ˈæpəl/")
        XCTAssertNil(model.phoneticStates["apple"])
    }
    @MainActor func testAutomaticQueryResumesAfterQuotaDeadline() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "wordshelf-test-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let replies = QuotaReplies()
        let model = Model(storeURL: folder.appendingPathComponent("words.sqlite"), collectorEnabled: false, loadCredential: false, preferences: preferences, requestInterval: 0.001, phoneticLookup: { _ in await replies.lookup() })
        try model.store!.save("apple"); model.reload(); model.hasPhoneticKey = true
        model.setAutomaticPhonetics(true)
        for _ in 0..<300 {
            if model.words.first?.phonetic.isEmpty == false { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        model.setAutomaticPhonetics(false)
        let times = await replies.times
        XCTAssertEqual(times.count, 2)
        if times.count == 2 { XCTAssertGreaterThanOrEqual(times[1].timeIntervalSince(times[0]), 0.075) }
        XCTAssertEqual(model.words.first?.phonetic, "/ˈæpəl/")
    }
    func testUnchangedDeniedPermissionOnlyNotifiesOnce() {
        let collector = LookupCollector(trustCheck: { false })
        var statusCount = 0, permissionCount = 0
        collector.onStatus = { _ in statusCount += 1 }
        collector.onPermission = { _ in permissionCount += 1 }
        collector.checkPermission(); collector.checkPermission(); collector.checkPermission()
        XCTAssertEqual(statusCount, 1)
        XCTAssertEqual(permissionCount, 1)
    }
    @MainActor func testUndoExpiresWithoutResurrectingDeletedWord() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "wordshelf-test-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let model = Model(storeURL: folder.appendingPathComponent("words.sqlite"), collectorEnabled: false, loadCredential: false, preferences: preferences, undoInterval: 0.02)
        try model.store!.save("apple"); model.reload(); model.deleteWord("apple")
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertTrue(model.deletedWords.isEmpty)
        model.undoDelete()
        XCTAssertTrue(model.words.isEmpty)
    }
}
