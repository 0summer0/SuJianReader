import Foundation

enum DocumentOrigin: String, Codable {
    case external

    case sharedFolder

    case importedCopy
}

struct ReadingRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var fileName: String
    var bookmark: Data
    var lastOpened: Date
    var byteCount: Int64
    var origin: DocumentOrigin
    var relativePath: String?

    var subtitle: String {
        let stem = (fileName as NSString).deletingPathExtension
        let when = ReadingDate.quiet(lastOpened)
        let size = ReadingDate.bytes(byteCount)
        if Self.sameName(title, stem) || Self.sameName(title, fileName) {
            return "\(when)  ·  \(size)"
        }
        return "\(fileName)  ·  \(when)  ·  \(size)"
    }

    private static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        folded(lhs) == folded(rhs)
    }

    private static func folded(_ text: String) -> String {
        text.filter { !$0.isWhitespace }.folding(options: .caseInsensitive, locale: Locale(identifier: "zh_CN"))
    }
}

struct DismissedSharedFile: Codable, Hashable {
    var relativePath: String
    var modifiedAt: Date
}

struct UnreadableInboxFile: Codable, Equatable {
    var fileName: String
    var byteCount: Int64
    var modifiedAt: Date

    var sampleDigest: Data?
}

enum ReadingDate {
    static func quiet(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "今天") }
        if calendar.isDateInYesterday(date) { return String(localized: "昨天") }
        let formatter = DateFormatter()
        formatter.locale = .current
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            formatter.setLocalizedDateFormatFromTemplate("Md")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("yMd")
        }
        return formatter.string(from: date)
    }

    static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let safe = max(count, 0)
        let display = safe < 1024 ? 1024 : safe
        formatter.allowedUnits = display < 1024 * 1024 ? .useKB : .useMB
        formatter.includesUnit = true
        return formatter.string(fromByteCount: display)
    }
}
