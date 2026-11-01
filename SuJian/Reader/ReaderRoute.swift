import Foundation

struct ReaderRoute: Hashable {
    var id: UUID
    var anchor: String?

    var token: UUID

    init(id: UUID, anchor: String? = nil) {
        self.id = id
        self.anchor = anchor
        self.token = UUID()
    }
}
