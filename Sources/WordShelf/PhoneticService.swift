import Foundation
import CryptoKit

enum PhoneticResult: Equatable {
    case found(String)
    case missing
    case failed(String)
    case blocked(String)
    case limited(Date)
}

actor PhoneticService {
    static let shared = PhoneticService()
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var pending: [String: Task<PhoneticResult, Never>] = [:]
    private var attempted: [String: Date] = [:]
    private var cache: [String: String] = [:]
    private let session: URLSession
    private let minimumInterval: TimeInterval
    private var apiKey: String?
    private let quotaDefaults: UserDefaults?
    private var nextRequestAt = Date.distantPast
    private var cooldownUntil = Date.distantPast
    private var limitCount = 0
    init(session: URLSession? = nil, minimumInterval: TimeInterval = 10, apiKey: String? = nil) {
        self.apiKey = apiKey
        self.quotaDefaults = session == nil ? .standard : nil
        self.minimumInterval = minimumInterval
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 15
            configuration.httpShouldSetCookies = false
            self.session = URLSession(configuration: configuration)
        }
    }
    func configure(key: String) {
        apiKey = key
        attempted.removeAll()
        cooldownUntil = .distantPast
    }
    func lookup(_ word: String, retry: Bool = false) async -> PhoneticResult {
        guard WordRules.normalize(word) == word else { return .missing }
        if let cached = cache[word] { return .found(cached) }
        if cooldownUntil > Date() { return .limited(cooldownUntil) }
        if let task = pending[word] { return await task.value }
        if !retry, let date = attempted[word], Date().timeIntervalSince(date) < 300 { return .failed("请稍后重试") }
        let task = Task { await self.fetch(word) }
        pending[word] = task
        let value = await task.value
        pending[word] = nil
        attempted[word] = Date()
        if case .found(let text) = value { cache[word] = text }
        return value
    }
    private func acquire() async {
        if active < 1 { active += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if waiters.isEmpty { active -= 1 }
        else { waiters.removeFirst().resume() }
    }
    private func fetch(_ word: String) async -> PhoneticResult {
        await acquire()
        defer { release() }
        if cooldownUntil > Date() { return .limited(cooldownUntil) }
        let wait = nextRequestAt.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        let key: String
        do {
            let storedKey = try apiKey ?? APIKeyStore.load()
            guard let stored = storedKey, !stored.isEmpty else { return .blocked("请先设置 API Key") }
            key = stored
        } catch { return .blocked("无法读取 API Key") }
        if let defaults = quotaDefaults,
           let _ = APIQuota.reserve(key: key, defaults: defaults) {
            return .blocked("今日免费额度已用完，明日再试")
        }
        let base = URL(string: "https://www.dictionaryapi.com/api/v3/references/learners/json")!.appendingPathComponent(word)
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        let url = components.url!
        do {
            let (data, response) = try await session.data(from: url)
            nextRequestAt = Date().addingTimeInterval(minimumInterval)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode
            if status == 429 {
                limitCount += 1
                let fallback = min(900.0, 60 * pow(2, Double(min(limitCount - 1, 4))))
                cooldownUntil = Self.retryDate(http?.value(forHTTPHeaderField: "Retry-After"), now: Date(), fallback: fallback)
                return .limited(cooldownUntil)
            }
            if status == 401 || status == 403 { return .blocked("Key 无效或不属于 Learner’s Dictionary") }
            if let message = String(data: data, encoding: .utf8), message.localizedCaseInsensitiveContains("invalid api key") {
                return .blocked("Key 无效或不属于 Learner’s Dictionary")
            }
            if status == 404 { limitCount = 0; return .missing }
            guard status == 200 else { return .failed("服务错误（HTTP \(status ?? 0)）") }
            limitCount = 0
            do {
                if let text = try Self.parse(data, word: word) { return .found(text) }
                return .missing
            } catch { return .failed("响应格式异常") }
        } catch {
            nextRequestAt = Date().addingTimeInterval(minimumInterval)
            return .failed("连接失败（\((error as NSError).code)）")
        }
    }
    nonisolated static func retryDate(_ header: String?, now: Date, fallback: TimeInterval) -> Date {
        if let header {
            if let seconds = TimeInterval(header.trimmingCharacters(in: .whitespacesAndNewlines)), seconds.isFinite, seconds >= 0 {
                return now.addingTimeInterval(max(2, seconds))
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: header), date > now { return date }
        }
        return now.addingTimeInterval(fallback)
    }
    nonisolated static func parse(_ data: Data, word: String) throws -> String? {
        struct Pronunciation: Decodable { let ipa: String? }
        struct Headword: Decodable { let hw: String; let prs: [Pronunciation]? }
        struct Inflection: Decodable {
            let spelling: String
            let prs: [Pronunciation]?
            enum CodingKeys: String, CodingKey { case spelling = "if", prs }
        }
        struct Entry: Decodable { let hwi: Headword?; let ins: [Inflection]? }
        if (try? JSONDecoder().decode([String].self, from: data)) != nil { return nil }
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        func normalized(_ spelling: String) -> String {
            spelling.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "’", with: "'").lowercased()
        }
        func ipa(_ pronunciations: [Pronunciation]?) -> String? {
            for pronunciation in pronunciations ?? [] {
                if let text = pronunciation.ipa?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    return text.hasPrefix("/") ? text : "/" + text + "/"
                }
            }
            return nil
        }
        for entry in entries {
            if let headword = entry.hwi, normalized(headword.hw) == word, let text = ipa(headword.prs) { return text }
            for inflection in entry.ins ?? [] where normalized(inflection.spelling) == word {
                if let text = ipa(inflection.prs) { return text }
            }
        }
        // Never substitute a lemma's pronunciation for an inflected word without its own IPA.
        return nil
    }

}

// Give never-tried words priority, then revisit the oldest unsuccessful attempt.
enum PhoneticQueue {
    static func next(in words: [Word], attempts: [String: Date]) -> Word? {
        words.filter { $0.phonetic.isEmpty }.min {
            let lhs = attempts[$0.text] ?? .distantPast
            let rhs = attempts[$1.text] ?? .distantPast
            if lhs == rhs { return $0.firstSavedAt > $1.firstSavedAt }
            return lhs < rhs
        }
    }
}

enum APIQuota {
    // Conservative rolling 24-hour window protects the personal free allowance.
    static func reserve(key: String, defaults: UserDefaults, now: Date = Date(), limit: Int = 1000) -> Date? {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let prefix = "mw-learners-quota." + hash
        var start = defaults.double(forKey: prefix + ".start")
        var count = defaults.integer(forKey: prefix + ".count")
        if start == 0 || now.timeIntervalSince1970 >= start + 86400 {
            start = now.timeIntervalSince1970; count = 0
            defaults.set(start, forKey: prefix + ".start")
        }
        if count >= limit { return Date(timeIntervalSince1970: start + 86400) }
        defaults.set(count + 1, forKey: prefix + ".count")
        return nil
    }
}
