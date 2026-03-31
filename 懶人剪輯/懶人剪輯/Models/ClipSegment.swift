import Foundation

struct ClipSegment: Identifiable {
    let id: UUID
    /// 對應原始 VideoClip 的 ID
    let clipID: UUID
    /// 在原始素材中的起始時間（秒）
    let startTime: Double
    /// 在原始素材中的結束時間（秒）
    let endTime: Double
    /// 片段音量調整（dB），0 表示原始音量
    var volumeDB: Float = 0

    var duration: Double { endTime - startTime }

    /// dB 轉線性音量倍數
    var linearVolume: Float {
        powf(10.0, volumeDB / 20.0)
    }

    init(clipID: UUID, startTime: Double, endTime: Double, volumeDB: Float = 0) {
        self.id = UUID()
        self.clipID = clipID
        self.startTime = startTime
        self.endTime = endTime
        self.volumeDB = volumeDB
    }
}
