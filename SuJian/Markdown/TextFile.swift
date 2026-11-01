import Foundation

enum TextFile {
    static func read(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard var text = decode(data) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        if text.hasPrefix("\u{feff}") {
            text.removeFirst()
        }
        return text
    }

    static func peekTitle(url: URL, fallback: String) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return fallback }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 16_384)) ?? Data()

        guard let text = decode(data, allowingIncompleteSuffix: data.count == 16_384) else { return fallback }
        return title(in: text, fallback: fallback)
    }

    static func title(in text: String, fallback: String) -> String {
        let content = text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("# ") else { continue }
            let raw = line.dropFirst(2).replacingOccurrences(of: "`", with: "")
            let title = raw.trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return title }
        }
        return fallback
    }

    private static func decode(_ data: Data, allowingIncompleteSuffix: Bool = false) -> String? {
        if data.isEmpty { return "" }

        // Detect UTF-16 first: its ASCII bytes can also form valid UTF-8.
        let utf16Encoding: String.Encoding?
        if data.starts(with: [0xFF, 0xFE]) {
            utf16Encoding = .utf16LittleEndian
        } else if data.starts(with: [0xFE, 0xFF]) {
            utf16Encoding = .utf16BigEndian
        } else {
            let bytes = Array(data.prefix(4096))
            let evenZeros = stride(from: 0, to: bytes.count, by: 2).filter { bytes[$0] == 0 }.count
            let oddZeros = stride(from: 1, to: bytes.count, by: 2).filter { bytes[$0] == 0 }.count
            if oddZeros >= 2, oddZeros > evenZeros * 2, oddZeros * 5 > bytes.count {
                utf16Encoding = .utf16LittleEndian
            } else if evenZeros >= 2, evenZeros > oddZeros * 2, evenZeros * 5 > bytes.count {
                utf16Encoding = .utf16BigEndian
            } else {
                utf16Encoding = nil
            }
        }

        func decode(_ encoding: String.Encoding) -> String? {
            if let text = String(data: data, encoding: encoding) { return text }
            guard allowingIncompleteSuffix else { return nil }

            for count in 1...min(4, data.count) {
                if let text = String(data: data.dropLast(count), encoding: encoding) { return text }
            }
            return nil
        }

        if let utf16Encoding, let text = decode(utf16Encoding) { return text }
        if let text = decode(.utf8) { return text }
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        if let text = decode(gb) { return text }
        if let text = decode(.utf16) { return text }
        if let text = decode(.utf16LittleEndian) { return text }
        if let text = decode(.utf16BigEndian) { return text }
        return nil
    }
}
