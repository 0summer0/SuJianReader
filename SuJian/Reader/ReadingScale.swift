import Foundation

struct ReadingScale: Identifiable, Hashable {
    var id: Double { value }
    var name: String
    var value: Double

    static let options: [ReadingScale] = [
        ReadingScale(name: "小", value: 0.85),
        ReadingScale(name: "中小", value: 0.92),
        ReadingScale(name: "标准", value: 1),
        ReadingScale(name: "中大", value: 1.08),
        ReadingScale(name: "大", value: 1.15)
    ]
}
