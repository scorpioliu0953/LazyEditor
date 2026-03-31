import Foundation

struct SilenceDetectionConfig {
    /// 音量閾值（dB），低於此值視為靜音。預設 -35 dB
    var thresholdDB: Float = Constants.defaultSilenceThresholdDB

    /// 最短靜音持續時間（秒）。短於此值的靜音不會被移除。預設 0.5 秒
    var minDuration: Double = Constants.defaultMinSilenceDuration

    /// 靜音邊緣預留間距（秒）。在有聲音的前後各保留此時長的緩衝，避免過度緊湊。
    var paddingDuration: Double = Constants.defaultSilencePadding

    /// 將 dB 閾值轉為線性振幅值
    nonisolated var linearThreshold: Float {
        powf(10.0, thresholdDB / 20.0)
    }
}
