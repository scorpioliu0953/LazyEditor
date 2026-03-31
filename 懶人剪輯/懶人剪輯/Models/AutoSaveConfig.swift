import Foundation
import Observation

@Observable
final class AutoSaveConfig {
    var enabled: Bool = false
    var folderURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    var intervalMinutes: Int = 5

    static let intervalOptions = [1, 3, 5, 10, 15]

    var intervalSeconds: TimeInterval {
        TimeInterval(intervalMinutes * 60)
    }
}
