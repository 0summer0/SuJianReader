import Foundation
import Markdown

enum HTMLText {
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func url(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isBlockedURL(value) { return nil }
        if let scheme = scheme(in: value) {
            if scheme == "http" || scheme == "https" || scheme == "mailto" {
                return escape(value)
            }
            return nil
        }
        return escape(value)
    }

    // Reject control characters before validating schemes: browsers may strip them.
    static func isBlockedURL(_ value: String) -> Bool {
        if value.isEmpty || value.contains(where: \.isNewline) { return true }
        if value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) { return true }
        let lower = value.lowercased()
        return lower.hasPrefix("javascript:") || lower.hasPrefix("vbscript:") || lower.hasPrefix("data:") || lower.hasPrefix("//")
    }

    static func scheme(in value: String) -> String? {
        guard let colon = value.firstIndex(of: ":") else { return nil }
        let scheme = value[..<colon].lowercased()
        guard !scheme.isEmpty, scheme.allSatisfy({ $0.isLetter || $0 == "+" || $0 == "." || $0 == "-" }) else { return nil }
        return scheme
    }
}

enum MarkdownRender {
    static func render(_ raw: String) -> RenderedMarkdown {
        let source = Footnotes.extract(normalize(raw))
        let document = Document(parsing: source.body)
        var walker = HTMLWalk(source: source.body, footnotes: source.definitions)
        walker.visit(document)
        walker.appendFootnotes()
        return RenderedMarkdown(
            bodyHTML: walker.html,
            outline: walker.outline,
            textCount: walker.textCount,
            hasH1: walker.hasH1,
            h1Text: walker.h1Text
        )
    }

    static func normalize(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if text.hasPrefix("\u{feff}") {
            text.removeFirst()
        }
        return strippingFrontMatter(text)
    }

    static func strippingFrontMatter(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "---" else { return text }
        let window = lines.dropFirst().prefix(40)
        guard let end = window.firstIndex(where: { $0 == "---" }) else { return text }
        return lines[lines.index(after: end)...].joined(separator: "\n")
    }
}

private struct HTMLWalk: MarkupWalker {
    var html = ""
    var outline: [OutlineEntry] = []
    var textCount = 0
    var hasH1 = false
    var h1Text: String?
    private var headingCount = 0
    private var outlineBuffer: String?
    private var slugs = HeadingSlugs()
    private var columnAlignments: [Table.ColumnAlignment?] = []
    private var linkDepth = 0

    private var lines: [Substring]
    private let footnotes: [String: String]
    private var footnoteOrder: [String] = []
    private var footnoteNumbers: [String: Int] = [:]
    private var footnoteRefs: [String: Int] = [:]
    private var inFootnote = false

    init(source: String, footnotes: [String: String]) {
        lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        self.footnotes = footnotes
    }

    mutating func visitHeading(_ heading: Heading) {
        let level = min(max(heading.level, 1), 6)
        headingCount += 1
        let anchor = "h\(headingCount)"
        let tracked = !inFootnote
        if level == 1, tracked { hasH1 = true }
        html += "<h\(level) id=\"\(anchor)\">"
        if let slug = slugs.next(for: plain(heading)) {
            html += "<span class=\"slug\" id=\"\(HTMLText.escape(slug))\"></span>"
        }
        if level <= 3, tracked { outlineBuffer = "" }
        inlines(Array(heading.children))
        if level <= 3, tracked, let text = outlineBuffer?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            outline.append(OutlineEntry(id: anchor, level: level, text: text))
            if level == 1, h1Text == nil { h1Text = text }
        }
        outlineBuffer = nil
        html += "</h\(level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        html += "<p>"
        inlines(Array(paragraph.children))
        html += "</p>\n"
    }

    mutating func visitText(_ text: Text) {
        inlines([text])
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        if outlineBuffer != nil { outlineBuffer?.append(" ") }
        html += "\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        html += "<br>\n"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        html += "<em>"
        inlines(Array(emphasis.children))
        html += "</em>"
    }

    mutating func visitStrong(_ strong: Strong) {
        html += "<strong>"
        inlines(Array(strong.children))
        html += "</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        let tag = isSubscript(strikethrough) ? "sub" : "del"
        html += "<\(tag)>"
        inlines(Array(strikethrough.children))
        html += "</\(tag)>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        if outlineBuffer != nil { outlineBuffer?.append(inlineCode.code) }
        count(inlineCode.code)
        html += "<code>\(HTMLText.escape(inlineCode.code))</code>"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        var code = codeBlock.code
        if code.hasSuffix("\n") { code.removeLast() }
        count(code)
        html += "<pre"
        if let language = languageToken(codeBlock.language) {
            html += " data-language=\"\(HTMLText.escape(language))\""
        }
        html += "><code>\(HTMLText.escape(code))</code></pre>\n"
    }

    mutating func visitLink(_ link: Link) {
        let href = HTMLText.url(link.destination)
        if let href {
            html += "<a href=\"\(href)\"\(titleAttribute(link.title))>"
        }
        linkDepth += 1
        inlines(Array(link.children))
        linkDepth -= 1
        if href != nil { html += "</a>" }
    }

    mutating func visitImage(_ image: Image) {
        let alt = plain(image)
        count(alt)
        guard let source = HTMLText.url(image.source) else {
            if !alt.isEmpty { html += HTMLText.escape(alt) }
            return
        }
        html += "<img src=\"\(source)\" alt=\"\(HTMLText.escape(alt))\"\(titleAttribute(image.title))>"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        guard let callout = callout(in: blockQuote) else {
            html += "<blockquote>\n"
            descendInto(blockQuote)
            html += "</blockquote>\n"
            return
        }
        let style = "callout \(callout.kind.style)"
        if let open = callout.foldOpen {
            html += "<details class=\"\(style)\"\(open ? " open" : "")>\n<summary class=\"callout-title\">"
        } else {
            html += "<blockquote class=\"\(style)\">\n<p class=\"callout-title\">"
        }
        if callout.title.isEmpty {
            emitText(callout.kind.title)
        } else {
            inlines(callout.title)
        }
        html += callout.foldOpen == nil ? "</p>\n" : "</summary>\n"
        if !callout.body.isEmpty {
            html += "<p>"
            inlines(callout.body)
            html += "</p>\n"
        }
        for child in blockQuote.children.dropFirst() {
            visit(child)
        }
        html += callout.foldOpen == nil ? "</blockquote>\n" : "</details>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        html += "<hr>\n"
    }

    mutating func visitHTMLBlock(_ htmlBlock: HTMLBlock) {
        switch SafeHTML.block(htmlBlock.rawHTML) {
        case .hidden:
            break
        case .rendered(let markup, let text):
            count(text)
            html += markup
            if !markup.hasSuffix("\n") { html += "\n" }
        case .source:
            html += "<pre class=\"raw\"><code>\(HTMLText.escape(htmlBlock.rawHTML))</code></pre>\n"
        }
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        let raw = inlineHTML.rawHTML
        if let safe = SafeHTML.inline(raw) {
            html += safe
            return
        }
        count(raw)
        html += HTMLText.escape(raw)
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        html += "<ul>\n"
        descendInto(unorderedList)
        html += "</ul>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        if orderedList.startIndex != 1 {
            html += "<ol start=\"\(orderedList.startIndex)\">\n"
        } else {
            html += "<ol>\n"
        }
        descendInto(orderedList)
        html += "</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) {
        if let checkbox = listItem.checkbox {
            let done = checkbox == .checked ? " done" : ""
            html += "<li class=\"task\(done)\"><span class=\"box\" aria-hidden=\"true\"></span>"
        } else {
            html += "<li>"
        }
        descendInto(listItem)
        html += "</li>\n"
    }

    mutating func visitTable(_ table: Table) {
        let outer = columnAlignments
        columnAlignments = table.columnAlignments
        html += "<div class=\"table-wrap\"><table>\n<thead>\n<tr>\n"
        tableCells(Array(table.head.cells), tag: "th")
        html += "</tr>\n</thead>\n"
        let rows = Array(table.body.rows)
        if !rows.isEmpty {
            html += "<tbody>\n"
            for row in rows {
                html += "<tr>\n"
                tableCells(Array(row.cells), tag: "td")
                html += "</tr>\n"
            }
            html += "</tbody>\n"
        }
        html += "</table></div>\n"
        columnAlignments = outer
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) {
        if let destination = symbolLink.destination {
            count(destination)
            html += "<code>\(HTMLText.escape(destination))</code>"
        }
    }

    mutating func appendFootnotes() {
        guard !footnoteOrder.isEmpty else { return }
        let bodyLines = lines
        let bodyHTML = html
        inFootnote = true
        var contents: [String] = []
        var index = 0
        while index < footnoteOrder.count {
            let source = footnotes[footnoteOrder[index]] ?? ""
            lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            html = ""
            visit(Document(parsing: source))
            contents.append(html)
            index += 1
        }
        inFootnote = false
        lines = bodyLines
        html = bodyHTML
        let footnotesTitle = HTMLText.escape(String(localized: "脚注"))
        let backLabel = HTMLText.escape(String(localized: "返回正文"))
        html += "<section class=\"footnotes\">\n<p class=\"footnotes-title\">\(footnotesTitle)</p>\n<ol>\n"
        for (offset, content) in contents.enumerated() {
            let number = offset + 1
            let refs = max(1, footnoteRefs[footnoteOrder[offset]] ?? 1)
            var back = ""
            for ref in 1...refs {
                let target = ref == 1 ? "fnref-\(number)" : "fnref-\(number)-\(ref)"
                let mark = ref == 1 ? "" : "<sup>\(ref)</sup>"
                back += " <a class=\"backref\" href=\"#\(target)\" aria-label=\"\(backLabel)\">↩\u{FE0E}\(mark)</a>"
            }
            var item = content
            if item.hasSuffix("</p>\n") {
                item.removeLast(5)
                item += back + "</p>\n"
            } else {
                item += "<p>" + back + "</p>\n"
            }
            html += "<li id=\"fn-\(number)\">\n\(item)</li>\n"
        }
        html += "</ol>\n</section>\n"
    }

    private enum Piece {
        case text(String)
        case mark
        case superscript(String)
        case footnote(String)
        case autolink(href: String, text: String)
        case node(Markup)
    }

    private struct Escaped {
        var references: Set<String.Index> = []
        var marks: Set<String.Index> = []
        var carets: Set<String.Index> = []
    }

    private mutating func inlines(_ nodes: [Markup]) {
        var pieces: [Piece] = []
        for node in nodes {
            if let text = node as? Text {
                split(text, into: &pieces)
            } else {
                pieces.append(.node(node))
            }
        }
        let marks = markRoles(pieces)
        for (index, piece) in pieces.enumerated() {
            switch piece {
            case .text(let string):
                emitText(string)
            case .mark:
                switch marks[index] {
                case true?: html += "<mark>"
                case false?: html += "</mark>"
                case nil: emitText("==")
                }
            case .superscript(let string):
                html += "<sup>"
                emitText(string)
                html += "</sup>"
            case .footnote(let key):
                emitFootnoteReference(key)
            case .autolink(let href, let text):
                html += "<a href=\"\(HTMLText.escape(href))\">"
                emitText(text)
                html += "</a>"
            case .node(let node):
                if node is SoftBreak,
                   let before = index > 0 ? Self.edge(of: pieces[index - 1], last: true) : nil,
                   let after = index + 1 < pieces.count ? Self.edge(of: pieces[index + 1], last: false) : nil,
                   CJK.isWide(before), CJK.isWide(after) {
                    if outlineBuffer != nil { outlineBuffer?.append(" ") }
                    continue
                }
                visit(node)
            }
        }
    }

    private mutating func emitText(_ string: String) {
        if outlineBuffer != nil { outlineBuffer?.append(string) }
        count(string)
        html += HTMLText.escape(string)
    }

    private mutating func emitFootnoteReference(_ key: String) {
        let number: Int
        if let known = footnoteNumbers[key] {
            number = known
        } else {
            footnoteOrder.append(key)
            number = footnoteOrder.count
            footnoteNumbers[key] = number
        }
        let ref = (footnoteRefs[key] ?? 0) + 1
        footnoteRefs[key] = ref
        let id = ref == 1 ? "fnref-\(number)" : "fnref-\(number)-\(ref)"
        html += "<sup class=\"fnref\"><a id=\"\(id)\" href=\"#fn-\(number)\">\(number)</a></sup>"
    }

    private func split(_ text: Text, into pieces: inout [Piece]) {
        let string = text.string
        let escaped = escapedMarkers(in: text)
        guard linkDepth == 0, !footnotes.isEmpty, string.contains("[^") else {
            appendPlain(string[...], escaped: escaped, to: &pieces)
            return
        }
        var cursor = string.startIndex
        var searchFrom = string.startIndex
        while let open = string.range(of: "[^", range: searchFrom..<string.endIndex) {
            searchFrom = open.upperBound
            guard !escaped.references.contains(open.lowerBound),
                  let close = string[open.upperBound...].firstIndex(of: "]") else { continue }
            let label = string[open.upperBound..<close]
            let key = Footnotes.key(label)
            guard Footnotes.isLabel(label), footnotes[key] != nil else { continue }
            appendPlain(string[cursor..<open.lowerBound], escaped: escaped, to: &pieces)
            pieces.append(.footnote(key))
            cursor = string.index(after: close)
            searchFrom = cursor
        }
        appendPlain(string[cursor...], escaped: escaped, to: &pieces)
    }

    private func appendPlain(_ string: Substring, escaped: Escaped, to pieces: inout [Piece]) {
        guard !string.isEmpty else { return }
        var cursor = string.startIndex
        if linkDepth == 0 {
            for link in Autolink.find(in: string) {
                Self.appendScripts(string[cursor..<link.range.lowerBound], escaped: escaped, to: &pieces)
                pieces.append(.autolink(href: link.href, text: String(string[link.range])))
                cursor = link.range.upperBound
            }
        }
        Self.appendScripts(string[cursor...], escaped: escaped, to: &pieces)
    }

    private static func appendScripts(_ string: Substring, escaped: Escaped, to pieces: inout [Piece]) {
        guard string.contains("^") else {
            appendMarks(string, escaped: escaped.marks, to: &pieces)
            return
        }
        func isCaret(_ index: String.Index) -> Bool {
            string[index] == "^" && !escaped.carets.contains(index)
        }
        var cursor = string.startIndex
        var i = string.startIndex
        while i < string.endIndex {
            guard isCaret(i), i == string.startIndex || string[string.index(before: i)] != "[" else {
                i = string.index(after: i)
                continue
            }
            let contentStart = string.index(after: i)
            guard let close = string[contentStart...].indices.first(where: isCaret) else { break }
            let content = string[contentStart..<close]
            guard isScriptContent(content) else {
                i = close
                continue
            }
            appendMarks(string[cursor..<i], escaped: escaped.marks, to: &pieces)
            pieces.append(.superscript(String(content)))
            cursor = string.index(after: close)
            i = cursor
        }
        appendMarks(string[cursor...], escaped: escaped.marks, to: &pieces)
    }

    private static func isScriptContent(_ content: Substring) -> Bool {
        !content.isEmpty && !content.contains { $0.isWhitespace || ($0.isPunctuation && !$0.isASCII) }
    }

    private static func appendMarks(_ string: Substring, escaped: Set<String.Index>, to pieces: inout [Piece]) {
        guard !string.isEmpty else { return }
        guard string.contains("==") else {
            pieces.append(.text(String(string)))
            return
        }
        var start = string.startIndex
        var i = string.startIndex
        while i < string.endIndex {
            guard string[i] == "=" else {
                i = string.index(after: i)
                continue
            }
            let runEnd = string[i...].firstIndex(where: { $0 != "=" }) ?? string.endIndex
            if string.distance(from: i, to: runEnd) == 2, !escaped.contains(i) {
                if start < i { pieces.append(.text(String(string[start..<i]))) }
                pieces.append(.mark)
                start = runEnd
            }
            i = runEnd
        }
        if start < string.endIndex { pieces.append(.text(String(string[start...]))) }
    }

    private func markRoles(_ pieces: [Piece]) -> [Int: Bool] {
        var roles: [Int: Bool] = [:]
        var opener: Int?
        for index in pieces.indices {
            guard case .mark = pieces[index] else { continue }
            let before = index > 0 ? Self.edge(of: pieces[index - 1], last: true) : nil
            let after = index + 1 < pieces.count ? Self.edge(of: pieces[index + 1], last: false) : nil
            let canOpen = after.map { !$0.isWhitespace } ?? false
            let canClose = before.map { !$0.isWhitespace } ?? false
            if let start = opener, canClose {
                roles[start] = true
                roles[index] = false
                opener = nil
            } else if canOpen {
                opener = index
            }
        }
        return roles
    }

    private static func edge(of piece: Piece, last: Bool) -> Character? {
        switch piece {
        case .text(let string), .superscript(let string), .autolink(_, let string):
            return last ? string.last : string.first
        case .mark:
            return "="
        case .footnote:
            return "1"
        case .node(let node):
            return edge(of: node, last: last)
        }
    }

    private static func edge(of node: Markup, last: Bool) -> Character? {
        if node is SoftBreak || node is LineBreak { return " " }
        if let text = node as? Text { return last ? text.string.last : text.string.first }
        if let code = node as? InlineCode { return last ? code.code.last : code.code.first }
        let children = Array(node.children)
        for child in last ? children.reversed() : children {
            if let character = edge(of: child, last: last) { return character }
        }
        return node.childCount == 0 ? "x" : nil
    }

    private func escapedMarkers(in text: Text) -> Escaped {
        let backslash = UInt8(ascii: "\\")
        let string = text.string
        guard string.contains("^") || string.contains("=="),
              let range = text.range, range.lowerBound.line == range.upperBound.line,
              lines.indices.contains(range.lowerBound.line - 1) else { return Escaped() }
        let bytes = Array(lines[range.lowerBound.line - 1].utf8)
        let start = range.lowerBound.column - 1
        let end = min(range.upperBound.column - 1, bytes.count)
        guard start >= 0, start <= end, bytes[start..<end].contains(backslash) else { return Escaped() }
        var codes: [UInt8] = []
        var escaped: [Bool] = []
        var i = start
        while i < end {
            if bytes[i] == backslash, i + 1 < end, Self.isASCIIPunctuation(bytes[i + 1]) {
                codes.append(bytes[i + 1])
                escaped.append(true)
                i += 2
            } else {
                codes.append(bytes[i])
                escaped.append(false)
                i += 1
            }
        }
        let raw = Self.markers(in: codes)
        let positions = Array(string.indices)
        let found = Self.markers(in: string.map { $0.asciiValue ?? 0 })
        var result = Escaped()
        if raw.references.count == found.references.count {
            for (rawAt, textAt) in zip(raw.references, found.references) where escaped[rawAt] || escaped[rawAt + 1] {
                result.references.insert(positions[textAt])
            }
        }
        if raw.marks.count == found.marks.count {
            for (rawAt, textAt) in zip(raw.marks, found.marks) where escaped[rawAt] || escaped[rawAt + 1] {
                result.marks.insert(positions[textAt])
            }
        }
        if raw.carets.count == found.carets.count {
            for (rawAt, textAt) in zip(raw.carets, found.carets) where escaped[rawAt] {
                result.carets.insert(positions[textAt])
            }
        }
        return result
    }

    private static func markers(in codes: [UInt8]) -> (references: [Int], marks: [Int], carets: [Int]) {
        var references: [Int] = []
        var marks: [Int] = []
        var carets: [Int] = []
        var i = 0
        while i < codes.count {
            if codes[i] == UInt8(ascii: "=") {
                var runEnd = i
                while runEnd < codes.count, codes[runEnd] == UInt8(ascii: "=") { runEnd += 1 }
                if runEnd - i == 2 { marks.append(i) }
                i = runEnd
                continue
            }
            if codes[i] == UInt8(ascii: "^") {
                carets.append(i)
            }
            if codes[i] == UInt8(ascii: "["), i + 1 < codes.count, codes[i + 1] == UInt8(ascii: "^") {
                references.append(i)
            }
            i += 1
        }
        return (references, marks, carets)
    }

    private static func isASCIIPunctuation(_ byte: UInt8) -> Bool {
        (0x21...0x2F).contains(byte) || (0x3A...0x40).contains(byte) || (0x5B...0x60).contains(byte) || (0x7B...0x7E).contains(byte)
    }

    private struct Callout {
        var kind: CalloutKind
        var foldOpen: Bool?
        var title: [Markup]
        var body: [Markup]
    }

    private func callout(in blockQuote: BlockQuote) -> Callout? {
        guard let paragraph = blockQuote.child(at: 0) as? Paragraph,
              let marker = paragraph.child(at: 0) as? Text else { return nil }
        let string = marker.string
        guard string.hasPrefix("[!"), let close = string.firstIndex(of: "]") else { return nil }
        let name = string[string.index(string.startIndex, offsetBy: 2)..<close]
        guard name.allSatisfy({ $0.isASCII && $0.isLetter }), let kind = CalloutKind(name.lowercased()) else { return nil }
        var rest = string[string.index(after: close)...]
        var foldOpen: Bool?
        if rest.first == "-" || rest.first == "+" {
            foldOpen = rest.first == "+"
            rest = rest.dropFirst()
        }
        guard rest.isEmpty || rest.first?.isWhitespace == true else { return nil }
        var title: [Markup] = []
        let leading = rest.drop(while: \.isWhitespace)
        if !leading.isEmpty { title.append(Text(String(leading))) }
        var body: [Markup] = []
        var inTitle = true
        for child in paragraph.children.dropFirst() {
            if inTitle, child is SoftBreak || child is LineBreak {
                inTitle = false
            } else if inTitle {
                title.append(child)
            } else {
                body.append(child)
            }
        }
        return Callout(kind: kind, foldOpen: foldOpen, title: title, body: body)
    }

    private mutating func tableCells(_ cells: [Table.Cell], tag: String) {
        for (column, cell) in cells.enumerated() {
            guard cell.colspan > 0, cell.rowspan > 0 else { continue }
            html += "<\(tag)"
            if column < columnAlignments.count {
                switch columnAlignments[column] {
                case .left?: html += " class=\"align-left\""
                case .center?: html += " class=\"align-center\""
                case .right?: html += " class=\"align-right\""
                case nil: break
                }
            }
            if cell.colspan > 1 { html += " colspan=\"\(cell.colspan)\"" }
            if cell.rowspan > 1 { html += " rowspan=\"\(cell.rowspan)\"" }
            html += ">"
            inlines(Array(cell.children))
            html += "</\(tag)>\n"
        }
    }

    private func isSubscript(_ strikethrough: Strikethrough) -> Bool {
        guard let range = strikethrough.range, lines.indices.contains(range.lowerBound.line - 1) else { return false }
        let line = lines[range.lowerBound.line - 1].utf8
        let start = range.lowerBound.column - 1
        guard start >= 0, start + 1 < line.count else { return false }
        let tilde = UInt8(ascii: "~")
        let first = line.index(line.startIndex, offsetBy: start)
        guard line[first] == tilde, line[line.index(after: first)] != tilde else { return false }
        return Self.isScriptContent(plain(strikethrough)[...])
    }

    private mutating func count(_ text: String) {
        for character in text where !character.isWhitespace {
            textCount += 1
        }
    }

    private func titleAttribute(_ title: String?) -> String {
        guard let title, !title.isEmpty else { return "" }
        return " title=\"\(HTMLText.escape(title))\""
    }

    private func languageToken(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.count < 32 else { return nil }
        let allowed = CharacterSet(charactersIn: "-_+#.")
        for scalar in token.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || allowed.contains(scalar) { continue }
            return nil
        }
        return token
    }

    private func plain(_ markup: Markup) -> String {
        var result = ""
        func walk(_ node: Markup) {
            if let text = node as? Text {
                result += text.string
                return
            }
            if let code = node as? InlineCode {
                result += code.code
                return
            }
            for child in node.children {
                walk(child)
            }
        }
        for child in markup.children {
            walk(child)
        }
        return result
    }
}

private struct CalloutKind {
    var style: String
    var title: String

    init?(_ name: String) {
        guard let entry = Self.names[name] else { return nil }
        style = entry.style
        title = entry.title
    }

    private static let names: [String: (style: String, title: String)] = [
        "note": ("note", String(localized: "备注")),
        "tip": ("tip", String(localized: "提示")),
        "important": ("important", String(localized: "重要")),
        "warning": ("warning", String(localized: "警告")),
        "caution": ("caution", String(localized: "当心")),
        "info": ("note", String(localized: "信息")),
        "abstract": ("note", String(localized: "摘要")),
        "summary": ("note", String(localized: "摘要")),
        "tldr": ("note", String(localized: "摘要")),
        "todo": ("note", String(localized: "待办")),
        "example": ("note", String(localized: "示例")),
        "quote": ("note", String(localized: "引述")),
        "cite": ("note", String(localized: "引述")),
        "hint": ("tip", String(localized: "提示")),
        "success": ("tip", String(localized: "完成")),
        "check": ("tip", String(localized: "完成")),
        "done": ("tip", String(localized: "完成")),
        "question": ("important", String(localized: "疑问")),
        "help": ("important", String(localized: "疑问")),
        "faq": ("important", String(localized: "疑问")),
        "attention": ("warning", String(localized: "警告")),
        "danger": ("caution", String(localized: "危险")),
        "error": ("caution", String(localized: "危险")),
        "failure": ("caution", String(localized: "失败")),
        "fail": ("caution", String(localized: "失败")),
        "missing": ("caution", String(localized: "失败")),
        "bug": ("caution", String(localized: "缺陷")),
    ]
}
