import Foundation

/// 文中の http と https の URL をリンクにする。
enum LinkedText {
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return result
        }
        let fullRange = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: fullRange) {
            // `example.md` のようなファイル名を、ドメインとみなしてリンクにしないよう、スキームを書いた URL だけを対象にする。
            guard let url = match.url, isWebURL(url),
                  let stringRange = Range(match.range, in: text),
                  text[stringRange].lowercased().hasPrefix("http"),
                  let range = Range(stringRange, in: result)
            else { continue }
            result[range].link = url
        }
        return result
    }

    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
