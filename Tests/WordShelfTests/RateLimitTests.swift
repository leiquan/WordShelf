import XCTest
@testable import WordShelf

private final class DictionaryStub: URLProtocol {
    static let lock = NSLock()
    static var status = 429
    static var body = Data()
    static var headers: [String: String] = [:]
    static var count = 0
    static var lastURL: URL?
    static func reset(status: Int, body: String = "", headers: [String: String] = [:]) {
        lock.lock(); defer { lock.unlock() }
        self.status = status; self.body = Data(body.utf8); self.headers = headers; count = 0; lastURL = nil
    }
    static func requestCount() -> Int { lock.lock(); defer { lock.unlock() }; return count }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.count += 1
        Self.lastURL = request.url
        let status = Self.status, body = Self.body, headers = Self.headers
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class RateLimitTests: XCTestCase {
    private func service() -> PhoneticService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DictionaryStub.self]
        return PhoneticService(session: URLSession(configuration: configuration), minimumInterval: 0, apiKey: "test-key")
    }
    func test429StopsFurtherRequestsEvenWithManualRetry() async {
        DictionaryStub.reset(status: 429, headers: ["Retry-After": "120"])
        let service = service()
        let start = Date()
        let first = await service.lookup("apple", retry: true)
        guard case .limited(let deadline) = first else { return XCTFail("Expected rate limit") }
        XCTAssertGreaterThanOrEqual(deadline.timeIntervalSince(start), 120)
        let second = await service.lookup("pear", retry: true)
        XCTAssertEqual(second, first)
        XCTAssertEqual(DictionaryStub.requestCount(), 1)
    }
    func testRetryAfterSecondsDateAndFallback() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(PhoneticService.retryDate("10", now: now, fallback: 60), now.addingTimeInterval(10))
        XCTAssertEqual(PhoneticService.retryDate("Thu, 01 Jan 1970 00:02:00 GMT", now: now, fallback: 60), now.addingTimeInterval(120))
        for header in [nil, "invalid", "-1", "nan"] as [String?] {
            XCTAssertEqual(PhoneticService.retryDate(header, now: now, fallback: 60), now.addingTimeInterval(60))
        }
    }
    func testHTTPAndParsingErrorsAreDistinct() async {
        DictionaryStub.reset(status: 503)
        let server = await service().lookup("apple", retry: true)
        XCTAssertEqual(server, .failed("服务错误（HTTP 503）"))
        DictionaryStub.reset(status: 200, body: "invalid JSON")
        let parse = await service().lookup("apple", retry: true)
        XCTAssertEqual(parse, .failed("响应格式异常"))
        DictionaryStub.reset(status: 404)
        let missing = await service().lookup("apple", retry: true)
        XCTAssertEqual(missing, .missing)
    }
    func testMerriamWebsterRequestAndCachedResult() async {
        DictionaryStub.reset(status: 200, body: #"[{"hwi":{"hw":"don't","prs":[{"ipa":"doʊnt"}]}}]"#)
        let service = service()
        let first = await service.lookup("don't", retry: true)
        XCTAssertEqual(first, .found("/doʊnt/"))
        let second = await service.lookup("don't", retry: true)
        XCTAssertEqual(second, first)
        XCTAssertEqual(DictionaryStub.requestCount(), 1)
        let url = DictionaryStub.lastURL!
        XCTAssertEqual(url.host, "www.dictionaryapi.com")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(url.path.hasPrefix("/api/v3/references/learners/json/"))
        XCTAssertEqual(url.lastPathComponent, "don't")
        XCTAssertEqual(items.first { $0.name == "key" }?.value, "test-key")
    }
}
