import Foundation

/// Small HTML helpers for recipe pages: entity decoding, tag stripping, turning
/// markup into readable lines, and reading attributes. Regex based on purpose:
/// recipe pages only need a few well-known structures, not a full DOM.
enum HTMLText {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "–", "mdash": "—", "hellip": "…", "rsquo": "’", "lsquo": "‘",
        "rdquo": "”", "ldquo": "“", "deg": "°", "frac12": "½", "frac14": "¼", "frac34": "¾",
        "frac13": "⅓", "frac23": "⅔", "frac18": "⅛", "eacute": "é", "egrave": "è", "ecirc": "ê",
        "aacute": "á", "agrave": "à", "acirc": "â", "iacute": "í", "oacute": "ó", "uacute": "ú",
        "ntilde": "ñ", "ccedil": "ç", "uuml": "ü", "ouml": "ö", "auml": "ä", "szlig": "ß",
        "times": "×", "copy": "©", "reg": "®", "trade": "™", "bull": "•", "middot": "·",
        "frasl": "⁄", "prime": "′", "Prime": "″",
    ]
    private static let entity = NSRegularExpression(compiling: #"&(#[0-9]+|#[xX][0-9a-fA-F]+|[A-Za-z][A-Za-z0-9]*);"#, options: [])
    private static let tag = NSRegularExpression(compiling: #"<[^>]*>"#)
    /// Inline tags vanish without a space so "<a>guide</a>." stays "guide.".
    private static let inlineTag = NSRegularExpression(compiling: #"</?(?:a|strong|em|b|i|u|span|sup|sub|small|mark)\b[^>]*>"#)
    private static let blockBreak = NSRegularExpression(compiling: #"<\s*(br|/p|/div|/li|/h[1-6]|/tr|/ol|/ul|/section|/header|/article)[^>]*>|<\s*(p|div|li|h[1-6]|tr|ol|ul|section)(\s[^>]*)?>"#)
    private static let listItem = NSRegularExpression(compiling: #"<\s*li(\s[^>]*)?>"#)
    private static let invisible = NSRegularExpression(compiling: #"<(script|style|noscript|svg|template|iframe|nav|footer)\b[^>]*>[\s\S]*?</\1\s*>|<!--[\s\S]*?-->"#)
    private static let whitespace = NSRegularExpression(compiling: #"[ \t\x{00A0}]+"#)

    /// Replaces `&amp;`, `&#8217;`, `&#x2019;` and friends. Runs twice for double-encoded pages.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = decodeOnce(text)
        if result.contains("&") { result = decodeOnce(result) }
        return result
    }

    private static func decodeOnce(_ text: String) -> String {
        let ns = text as NSString
        var output = ""
        var last = 0
        for match in entity.matches(in: text) {
            output += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let name = ns.substring(with: match.range(at: 1))
            output += replacement(for: name) ?? ns.substring(with: match.range)
            last = match.range.location + match.range.length
        }
        output += ns.substring(from: last)
        return output
    }

    private static func replacement(for name: String) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let code = digits.first == "x" || digits.first == "X"
                ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits, radix: 10)
            return code.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return named[name]
    }

    /// Plain text from a fragment: tags removed, entities decoded, spaces collapsed.
    static func plainText(_ html: String) -> String {
        let withoutInline = inlineTag.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: "")
        let withoutTags = tag.stringByReplacingMatches(in: withoutInline, range: NSRange(withoutInline.startIndex..., in: withoutInline), withTemplate: " ")
        return collapse(decodeEntities(withoutTags))
    }

    /// Readable lines from a page or fragment: block elements become line breaks and
    /// list items get a bullet, so a heuristic parser can work on the result.
    static func lines(fromHTML html: String) -> [String] {
        var text = invisible.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: " ")
        text = listItem.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\n• ")
        text = blockBreak.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\n")
        text = tag.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        text = decodeEntities(text)
        return text.components(separatedBy: .newlines)
            .map(collapse)
            .filter { !$0.isEmpty && $0 != "•" }
    }

    /// Collapses runs of spaces and trims.
    static func collapse(_ text: String) -> String {
        whitespace.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The value of `attribute` in a start tag such as `<meta property="og:image" content="...">`.
    static func attribute(_ attribute: String, in startTag: String) -> String? {
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: attribute) + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        let regex = NSRegularExpression(compiling: pattern)
        guard let match = regex.firstMatch(in: startTag, range: NSRange(startTag.startIndex..., in: startTag)) else { return nil }
        let value = match.group(1, in: startTag) ?? match.group(2, in: startTag) ?? match.group(3, in: startTag)
        return value.map(decodeEntities)
    }

    /// The `content` of a `<meta>` tag whose `property` or `name` is `key`, for Open Graph data.
    static func meta(_ key: String, in html: String) -> String? {
        let pattern = #"<meta\b[^>]*(?:property|name|itemprop)\s*=\s*["']"# + NSRegularExpression.escapedPattern(for: key) + #"["'][^>]*>"#
        let regex = NSRegularExpression(compiling: pattern)
        guard let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = match.swiftRange(in: html) else { return nil }
        return attribute("content", in: String(html[range])).map(collapse).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The text of the first element named `tag`, for example the page's `<title>` or `<h1>`.
    static func firstElementText(_ tagName: String, in html: String) -> String? {
        let regex = NSRegularExpression(compiling: "<" + tagName + #"\b[^>]*>([\s\S]*?)</"# + tagName + #"\s*>"#)
        guard let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let inner = match.group(1, in: html) else { return nil }
        let text = plainText(inner)
        return text.isEmpty ? nil : text
    }
}
