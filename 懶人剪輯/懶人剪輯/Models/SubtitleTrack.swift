import Foundation
import Observation

enum SubtitleLanguage: String, CaseIterable, Identifiable {
    case chinese = "中文"
    case english = "English"
    case japanese = "日本語"
    case korean = "한국어"
    case other = "其他"

    var id: String { rawValue }
}

@Observable
final class SubtitleTrack {
    var entries: [SubtitleEntry] = []
    var settings = SubtitleSettings()
    var language: SubtitleLanguage = .chinese
    var isVisible: Bool = true

    /// 根據時間查找當前活動的字幕
    func activeEntry(at time: Double) -> SubtitleEntry? {
        entries.first { time >= $0.startTime && time < $0.endTime }
    }
}
