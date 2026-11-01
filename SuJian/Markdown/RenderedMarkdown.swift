import Foundation

struct OutlineEntry: Identifiable, Hashable {
    var id: String
    var level: Int
    var text: String
}

struct RenderedMarkdown: Equatable {
    var bodyHTML: String
    var outline: [OutlineEntry]
    var textCount: Int
    var hasH1: Bool
    var h1Text: String?
}
