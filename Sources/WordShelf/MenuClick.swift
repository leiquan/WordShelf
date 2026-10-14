import Foundation
import CoreGraphics

/// Accept only an explicit system-style quoted Look Up title, never selection text.
enum LookupTitle {
    static func word(_ title: String) -> String? {
        let patterns = [
            "^Look Up [“\"]([A-Za-z]+(?:['’-][A-Za-z]+)*)[”\"](?:\\.{3}|…)?$",
            "^查[询找]\\s*[“\"]([A-Za-z]+(?:['’-][A-Za-z]+)*)[”\"](?:\\.{3}|…)?$"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                  let range = Range(match.range(at: 1), in: title) else { continue }
            return WordRules.normalize(String(title[range]))
        }
        return nil
    }
}

struct MenuClick {
    let word: String
    let bounds: CGRect
    let timestamp: TimeInterval
    func released(at point: CGPoint, timestamp: TimeInterval) -> String? {
        guard timestamp >= self.timestamp, timestamp - self.timestamp <= 10,
              bounds.contains(point) else { return nil }
        return word
    }
}
