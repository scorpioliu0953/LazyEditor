import Foundation

struct SubtitleEntry: Identifiable, Equatable {
    let id: UUID
    var startTime: Double
    var endTime: Double
    var text: String

    var duration: Double { endTime - startTime }

    init(id: UUID = UUID(), startTime: Double, endTime: Double, text: String) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}
