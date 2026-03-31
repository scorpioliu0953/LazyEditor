import Foundation
import Observation

@Observable
final class TextCardTrack {
    var entries: [TextCardEntry] = []

    /// 查找指定時間點的所有活動字卡
    func activeEntries(at time: Double) -> [TextCardEntry] {
        entries.filter { time >= $0.startTime && time < $0.endTime }
    }

    /// 新增字卡
    func addEntry(_ entry: TextCardEntry) {
        entries.append(entry)
    }

    /// 移除字卡
    func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
    }
}
