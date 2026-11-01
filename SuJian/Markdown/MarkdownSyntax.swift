import Foundation

enum Footnotes {
    struct Extraction {
        var body: String
        var definitions: [String: String]
    }

    static func key(_ label: Substring) -> String {
        label.lowercased()
    }

    static func isLabel(_ label: Substring) -> Bool {
        !label.isEmpty && label.count <= 200 && !label.contains(where: { $0.isWhitespace || $0 == "[" || $0 == "]" })
    }

    static func extract(_ source: String) -> Extraction {
        guard source.contains("[^") else { return Extraction(body: source, definitions: [:]) }
        var body: [Substring] = []
        var definitions: [String: String] = [:]
        var fence = Fence()
        var open: Definition?

        func finish(_ definition: Definition) {
            if definitions[definition.key] == nil {
                definitions[definition.key] = definition.lines.joined(separator: "\n")
            }
        }

        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            if var definition = open {
                if isBlank(line) {
                    definition.blanks += 1
                    open = definition
                    continue
                }
                if indent(of: line) >= 4 {
                    definition.lines += Array(repeating: "", count: definition.blanks)
                    definition.lines.append(dedent(line))
                    definition.blanks = 0
                    definition.lazy = true
                    open = definition
                    continue
                }
                if definition.blanks == 0, definition.lazy, !startsBlock(line) {
                    definition.lines.append(String(line))
                    open = definition
                    continue
                }
                body += Array(repeating: "", count: definition.blanks)
                finish(definition)
                open = nil
            }
            if fence.consume(line) {
                body.append(line)
                continue
            }
            if let start = definitionStart(line) {
                open = Definition(key: key(start.label), lines: [String(start.content)], lazy: !start.content.isEmpty)
                body.append("")
                continue
            }
            body.append(line)
        }
        if let open { finish(open) }
        return Extraction(body: body.joined(separator: "\n"), definitions: definitions)
    }

    private struct Definition {
        var key: String
        var lines: [String]
        var blanks = 0
        var lazy: Bool
    }

    private static func definitionStart(_ line: Substring) -> (label: Substring, content: Substring)? {
        let rest = line.drop(while: { $0 == " " })
        guard line.count - rest.count < 4, rest.hasPrefix("[^") else { return nil }
        let labelStart = rest.index(rest.startIndex, offsetBy: 2)
        guard let close = rest[labelStart...].firstIndex(of: "]") else { return nil }
        let label = rest[labelStart..<close]
        let colon = rest.index(after: close)
        guard isLabel(label), colon < rest.endIndex, rest[colon] == ":" else { return nil }
        let content = rest[rest.index(after: colon)...].drop(while: { $0 == " " || $0 == "\t" })
        return (label, content)
    }

    private static func startsBlock(_ line: Substring) -> Bool {
        if definitionStart(line) != nil { return true }
        let rest = line.drop(while: { $0 == " " })
        guard line.count - rest.count < 4, let first = rest.first else { return false }
        switch first {
        case "#":
            let marks = rest.prefix(while: { $0 == "#" })
            return marks.count <= 6 && (rest.count == marks.count || rest.dropFirst(marks.count).first?.isWhitespace == true)
        case ">":
            return true
        case "`", "~":
            return rest.hasPrefix("```") || rest.hasPrefix("~~~")
        case "<":
            guard let next = rest.dropFirst().first else { return false }
            return next.isLetter || next == "/" || next == "!"
        case "-", "*", "+", "_":
            if first != "_", rest.dropFirst().first?.isWhitespace == true { return true }
            let marks = rest.filter { !$0.isWhitespace }
            return marks.count >= 3 && marks.allSatisfy { $0 == first }
        default:
            return listMarkerLength(rest) != nil
        }
    }

    static func isBlank(_ line: Substring) -> Bool {
        line.allSatisfy { $0 == " " || $0 == "\t" }
    }

    static func indent(of line: Substring) -> Int {
        var width = 0
        for character in line {
            if character == " " {
                width += 1
            } else if character == "\t" {
                width += 4 - width % 4
            } else {
                break
            }
        }
        return width
    }

    private static func dedent(_ line: Substring) -> String {
        var width = 0
        var i = line.startIndex
        while i < line.endIndex, width < 4 {
            if line[i] == " " {
                width += 1
            } else if line[i] == "\t" {
                width += 4 - width % 4
            } else {
                break
            }
            i = line.index(after: i)
        }
        return String(repeating: " ", count: max(0, width - 4)) + line[i...]
    }

    static func listMarkerLength(_ text: Substring) -> Int? {
        guard let first = text.first else { return nil }
        if first == "-" || first == "*" || first == "+" {
            return text.dropFirst().first == " " ? 2 : nil
        }
        let digits = text.prefix(while: { $0.isASCII && $0.isNumber })
        guard (1...9).contains(digits.count) else { return nil }
        let after = text.dropFirst(digits.count)
        guard let delimiter = after.first, delimiter == "." || delimiter == ")", after.dropFirst().first == " " else {
            return nil
        }
        return digits.count + 2
    }

    private struct Fence {
        private var marker: Character?
        private var length = 0
        private var column = 0
        private var quoted = false
        private var nested = false

        mutating func consume(_ line: Substring) -> Bool {
            let prefix = Self.containerPrefix(line)
            if let marker {
                if !Footnotes.isBlank(line) {
                    if quoted, !prefix.quoted {
                        self.marker = nil
                        return false
                    }
                    if nested, !prefix.quoted, Footnotes.indent(of: line) < column {
                        self.marker = nil
                        return false
                    }
                }
                let content = prefix.rest.drop(while: { $0 == " " })
                let run = content.prefix(while: { $0 == marker })
                if run.count >= length, content.dropFirst(run.count).allSatisfy(\.isWhitespace) {
                    self.marker = nil
                }
                return true
            }
            let rest = prefix.rest
            guard let first = rest.first, first == "`" || first == "~" else { return false }
            let run = rest.prefix(while: { $0 == first })
            guard run.count >= 3 else { return false }
            if first == "`", rest.dropFirst(run.count).contains("`") { return false }
            marker = first
            length = run.count
            column = prefix.column
            quoted = prefix.quoted
            nested = prefix.listed || prefix.column >= 4
            return true
        }

        private static func containerPrefix(_ line: Substring) -> (rest: Substring, column: Int, quoted: Bool, listed: Bool) {
            var rest = line
            var column = 0
            var quoted = false
            while true {
                let trimmed = rest.drop(while: { $0 == " " || $0 == "\t" })
                column += rest.count - trimmed.count
                rest = trimmed
                guard rest.first == ">" else { break }
                quoted = true
                rest = rest.dropFirst()
                column += 1
            }
            var listed = false
            if let marker = Footnotes.listMarkerLength(rest) {
                listed = true
                rest = rest.dropFirst(marker)
                let trimmed = rest.drop(while: { $0 == " " })
                column += marker + rest.count - trimmed.count
                rest = trimmed
            }
            return (rest, column, quoted, listed)
        }
    }
}

enum Autolink {
    struct Match {
        var range: Range<String.Index>
        var href: String
    }

    private static let candidate = try! Regex(
        #"(?:https?://|www\.)[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*(?::[0-9]{1,5})?(?:[/?#][!-;=?-~]*)?|[A-Za-z0-9._+-]+@[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+"#
    ).ignoresCase()

    static func find(in text: Substring) -> [Match] {
        let lower = text.lowercased()
        guard lower.contains("://") || lower.contains("www.") || text.contains("@") else { return [] }
        var result: [Match] = []
        for match in text.matches(of: candidate) {
            let start = match.range.lowerBound
            if start > text.startIndex {
                let previous = text[text.index(before: start)]
                if previous.isASCII, previous.isLetter || previous.isNumber || previous == "/" || previous == "@" { continue }
            }
            let found = text[match.range]
            let lowerFound = found.lowercased()
            let www = lowerFound.hasPrefix("www.")
            if www || lowerFound.hasPrefix("http") {
                let end = trimmedEnd(of: found)
                let url = found[..<end]
                guard www ? url.count > 4 : !url.hasSuffix("://") else { continue }
                let href = www ? "https://" + url : String(url)
                result.append(Match(range: start..<end, href: href))
            } else {
                guard let last = found.last, last != "-", last != "_" else { continue }
                result.append(Match(range: match.range, href: "mailto:" + found))
            }
        }
        return result
    }

    private static func trimmedEnd(of url: Substring) -> String.Index {
        var end = url.endIndex
        while end > url.startIndex {
            let last = url[url.index(before: end)]
            if last == ";" {
                let head = url[..<url.index(before: end)]
                let name = head.reversed().prefix(while: { $0.isASCII && ($0.isLetter || $0.isNumber) })
                let ampersand = head.index(head.endIndex, offsetBy: -name.count)
                if !name.isEmpty, ampersand > head.startIndex, head[head.index(before: ampersand)] == "&" {
                    end = head.index(before: ampersand)
                } else {
                    end = url.index(before: end)
                }
                continue
            }
            if "?!.,:*_~'\"".contains(last) {
                end = url.index(before: end)
                continue
            }
            if last == ")" {
                let body = url[..<end]
                if body.filter({ $0 == ")" }).count > body.filter({ $0 == "(" }).count {
                    end = url.index(before: end)
                    continue
                }
            }
            break
        }
        return end
    }
}

struct HeadingSlugs {
    private var occurrences: [String: Int] = [:]

    mutating func next(for text: String) -> String? {
        let base = Self.slug(text)
        guard !base.isEmpty else { return nil }
        var slug = base
        while occurrences[slug] != nil {
            occurrences[base, default: 0] += 1
            slug = "\(base)-\(occurrences[base] ?? 0)"
        }
        occurrences[slug] = 0
        return slug
    }

    static func slug(_ text: String) -> String {
        var result = ""
        for character in text.lowercased() {
            if character == " " {
                result.append("-")
            } else if character == "-" || character == "_" || character.isLetter || character.isNumber {
                result.append(character)
            }
        }
        return result
    }
}

enum CJK {
    static func isWide(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x1100...0x115F, 0xAC00...0xD7A3:
            return false
        case 0x2E80...0x303F, 0x3040...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60, 0xFFE0...0xFFE6,
             0x20000...0x3FFFD:
            return true
        default:
            return false
        }
    }
}
