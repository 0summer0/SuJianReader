import Foundation

// Sanitize raw HTML; unsupported tags must be rendered as text.
enum SafeHTML {
    enum Block: Equatable {
        case hidden
        case rendered(html: String, text: String)
        case source
    }

    static func block(_ raw: String) -> Block {
        guard let cleaned = clean(raw) else { return .source }
        if cleaned.html.allSatisfy(\.isWhitespace) { return .hidden }
        return .rendered(html: cleaned.html, text: cleaned.text)
    }

    static func inline(_ raw: String) -> String? {
        clean(raw)?.html
    }

    private static let allowed: [String: Set<String>] = {
        var tags: [String: Set<String>] = [
            "a": ["href", "title", "name", "id"],
            "abbr": ["title"],
            "details": ["open"],
            "dfn": ["title"],
            "div": ["align"],
            "img": ["src", "alt", "title", "width", "height"],
            "ol": ["start"],
            "p": ["align"],
            "td": ["align", "colspan", "rowspan"],
            "th": ["align", "colspan", "rowspan"],
        ]
        for level in 1...6 {
            tags["h\(level)"] = ["align"]
        }
        let plain = [
            "b", "bdi", "blockquote", "br", "caption", "center", "cite", "code", "dd", "del", "dl", "dt",
            "em", "figcaption", "figure", "hr", "i", "ins", "kbd", "li", "mark", "picture", "pre", "q",
            "rp", "rt", "ruby", "s", "samp", "small", "span", "strike", "strong", "sub", "summary", "sup",
            "table", "tbody", "tfoot", "thead", "tr", "u", "ul", "var", "wbr",
        ]
        for tag in plain where tags[tag] == nil {
            tags[tag] = []
        }
        return tags
    }()

    private static let dropped: Set<String> = ["source", "track", "col", "colgroup"]
    private static let void: Set<String> = ["br", "hr", "img", "wbr", "source", "track", "col"]

    private struct Cleaned {
        var html = ""
        var text = ""
    }

    private static func clean(_ raw: String) -> Cleaned? {
        var out = Cleaned()
        var i = raw.startIndex
        while i < raw.endIndex {
            let rest = raw[i...]
            if rest.hasPrefix("<!--") {
                let body = raw.index(i, offsetBy: 4)
                i = raw.range(of: "-->", range: body..<raw.endIndex)?.upperBound ?? raw.endIndex
                continue
            }
            let character = raw[i]
            switch character {
            case "<":
                if let tag = Tag(parsing: rest) {
                    guard let safe = tag.sanitized() else { return nil }
                    out.html += safe
                    i = tag.end
                    continue
                }
                if let next = rest.dropFirst().first, next == "!" || next == "?" { return nil }
                out.html += "&lt;"
                out.text.append(character)
            case ">":
                out.html += "&gt;"
                out.text.append(character)
            case "&":
                if let length = entityLength(rest) {
                    let end = raw.index(i, offsetBy: length)
                    out.html += raw[i..<end]
                    out.text.append(character)
                    i = end
                    continue
                }
                out.html += "&amp;"
                out.text.append(character)
            default:
                out.html.append(character)
                out.text.append(character)
            }
            i = raw.index(after: i)
        }
        return out
    }

    private struct Tag {
        var name: String
        var closing: Bool
        var attributes: [(name: String, value: String?)]
        var end: String.Index

        init?(parsing s: Substring) {
            var i = s.index(after: s.startIndex)
            closing = false
            if i < s.endIndex, s[i] == "/" {
                closing = true
                i = s.index(after: i)
            }
            let nameStart = i
            guard i < s.endIndex, s[i].isASCII, s[i].isLetter else { return nil }
            while i < s.endIndex, s[i].isASCII, s[i].isLetter || s[i].isNumber || s[i] == "-" {
                i = s.index(after: i)
            }
            name = s[nameStart..<i].lowercased()
            attributes = []
            while true {
                let beforeSpace = i
                while i < s.endIndex, s[i].isWhitespace { i = s.index(after: i) }
                guard i < s.endIndex else { return nil }
                if s[i] == ">" {
                    end = s.index(after: i)
                    return
                }
                if s[i] == "/" {
                    let next = s.index(after: i)
                    guard next < s.endIndex, s[next] == ">" else { return nil }
                    end = s.index(after: next)
                    return
                }
                guard !closing, i > beforeSpace else { return nil }
                let attributeStart = i
                guard s[i].isASCII, s[i].isLetter || s[i] == "_" || s[i] == ":" else { return nil }
                while i < s.endIndex, s[i].isASCII, s[i].isLetter || s[i].isNumber || "_.:-".contains(s[i]) {
                    i = s.index(after: i)
                }
                let attributeName = s[attributeStart..<i].lowercased()
                var value: String?
                var j = i
                while j < s.endIndex, s[j].isWhitespace { j = s.index(after: j) }
                if j < s.endIndex, s[j] == "=" {
                    j = s.index(after: j)
                    while j < s.endIndex, s[j].isWhitespace { j = s.index(after: j) }
                    guard j < s.endIndex else { return nil }
                    if s[j] == "\"" || s[j] == "'" {
                        let valueStart = s.index(after: j)
                        guard let close = s[valueStart...].firstIndex(of: s[j]) else { return nil }
                        value = String(s[valueStart..<close])
                        i = s.index(after: close)
                    } else {
                        let valueStart = j
                        while j < s.endIndex, !s[j].isWhitespace, !"\"'=<>`".contains(s[j]) {
                            j = s.index(after: j)
                        }
                        guard j > valueStart else { return nil }
                        value = String(s[valueStart..<j])
                        i = j
                    }
                }
                attributes.append((attributeName, value))
            }
        }

        func sanitized() -> String? {
            if SafeHTML.dropped.contains(name) { return "" }
            guard let permitted = SafeHTML.allowed[name] else { return nil }
            if closing {
                return SafeHTML.void.contains(name) ? "" : "</\(name)>"
            }
            var out = "<\(name)"
            var hasSource = false
            var seen: Set<String> = []
            for attribute in attributes where permitted.contains(attribute.name) {
                guard let rendered = SafeHTML.attribute(attribute.name, attribute.value) else { continue }
                let key = rendered.name
                guard seen.insert(key).inserted else { continue }
                if key == "src" { hasSource = true }
                out += rendered.markup
            }
            if name == "img", !hasSource { return "" }
            return out + ">"
        }
    }

    private static func attribute(_ name: String, _ raw: String?) -> (name: String, markup: String)? {
        let value = raw.map(decodeEntities)
        switch name {
        case "href", "src":
            guard let url = HTMLText.url(value) else { return nil }
            return (name, " \(name)=\"\(url)\"")
        case "title", "alt":
            return (name, " \(name)=\"\(HTMLText.escape(value ?? ""))\"")
        case "width", "height":
            guard let value else { return nil }
            var digits = Substring(value)
            if digits.hasSuffix("%") {
                digits = digits.dropLast()
            } else if digits.hasSuffix("px") {
                digits = digits.dropLast(2)
            }
            guard (1...4).contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return (name, " \(name)=\"\(value)\"")
        case "colspan", "rowspan", "start":
            guard let value, (1...4).contains(value.count), value.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return (name, " \(name)=\"\(value)\"")
        case "align":
            guard let value = value?.lowercased(), ["left", "center", "right", "justify"].contains(value) else { return nil }
            return ("class", " class=\"align-\(value)\"")
        case "open":
            return (name, " open")
        case "id", "name":
            guard let value, (1...64).contains(value.count),
                  value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
            return ("id", " id=\"\(HTMLText.escape(value))\"")
        default:
            return nil
        }
    }

    private static func entityLength(_ s: Substring) -> Int? {
        var rest = s.dropFirst()
        if rest.first == "#" {
            rest = rest.dropFirst()
            var length = 2
            var hex = false
            if rest.first == "x" || rest.first == "X" {
                hex = true
                rest = rest.dropFirst()
                length += 1
            }
            let digits = rest.prefix { hex ? $0.isHexDigit : ($0.isASCII && $0.isNumber) }
            guard (1...7).contains(digits.count), rest.dropFirst(digits.count).first == ";" else { return nil }
            return length + digits.count + 1
        }
        let name = rest.prefix { $0.isASCII && ($0.isLetter || $0.isNumber) }
        guard (2...32).contains(name.count), name.first?.isLetter == true,
              rest.dropFirst(name.count).first == ";" else { return nil }
        return 1 + name.count + 1
    }

    private static func decodeEntities(_ value: String) -> String {
        guard value.contains("&") else { return value }
        var out = ""
        var i = value.startIndex
        while i < value.endIndex {
            if value[i] == "&", let length = entityLength(value[i...]) {
                let end = value.index(i, offsetBy: length)
                if let decoded = decodeEntity(value[value.index(after: i)..<value.index(before: end)]) {
                    out += decoded
                    i = end
                    continue
                }
            }
            out.append(value[i])
            i = value.index(after: i)
        }
        return out
    }

    private static func decodeEntity(_ body: Substring) -> String? {
        switch body {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return "\u{a0}"
        default: break
        }
        guard body.hasPrefix("#") else { return nil }
        var digits = body.dropFirst()
        var radix = 10
        if digits.first == "x" || digits.first == "X" {
            digits = digits.dropFirst()
            radix = 16
        }
        guard let code = UInt32(digits, radix: radix), code != 0, let scalar = Unicode.Scalar(code) else { return nil }
        return String(scalar)
    }
}
