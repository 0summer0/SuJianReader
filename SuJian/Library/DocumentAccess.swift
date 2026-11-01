import Foundation

struct DocumentAccess {
    let url: URL
    let started: Bool
    let byteCount: Int64

    func stop() {
        guard started else { return }
        url.stopAccessingSecurityScopedResource()
    }
}

// Keep security-scoped access alive for the lifetime of the reader.
final class OpenedDocument {
    let url: URL
    let text: String
    let byteCount: Int64
    private var startedAccess: Bool
    private var closed = false

    init(url: URL, text: String, byteCount: Int64, startedAccess: Bool) {
        self.url = url
        self.text = text
        self.byteCount = byteCount
        self.startedAccess = startedAccess
    }

    func close() {
        guard !closed else { return }
        closed = true
        if startedAccess {
            url.stopAccessingSecurityScopedResource()
            startedAccess = false
        }
    }

    deinit { close() }
}
