import SwiftUI
import CoreMedia

nonisolated enum Constants {
    // MARK: - 支援格式
    static let supportedVideoTypes: [String] = ["mp4", "mov", "m4v"]

    // MARK: - 時間軸
    static let defaultPixelsPerSecond: CGFloat = 100
    static let minPixelsPerSecond: CGFloat = 20
    static let maxPixelsPerSecond: CGFloat = 500
    static let playheadWidth: CGFloat = 2
    static let segmentCornerRadius: CGFloat = 4
    static let segmentSpacing: CGFloat = 1
    static let segmentTrackHeight: CGFloat = 64
    static let audioTrackHeight: CGFloat = 80
    static let timeRulerHeight: CGFloat = 24
    static let trackLabelWidth: CGFloat = 28

    // MARK: - 波形
    static let waveformBinsPerSecond: Int = 20
    static let waveformSampleRate: Double = 44100
    static let waveformSamplesPerBin: Int = 2205 // 44100 / 20

    // MARK: - FCP 風格顏色
    static let timelineBg = Color(white: 0.13)
    static let trackBg = Color(white: 0.17)
    static let trackLabelBg = Color(white: 0.11)
    static let rulerBg = Color(white: 0.15)
    static let rulerText = Color(white: 0.55)
    static let rulerTick = Color(white: 0.35)

    static let segmentFill = Color(red: 0.28, green: 0.45, blue: 0.70)
    static let segmentSelectedBorder = Color(red: 0.40, green: 0.70, blue: 1.0)
    static let audioSegmentFill = Color(red: 0.18, green: 0.35, blue: 0.22)

    static let waveformColor = Color(red: 0.35, green: 0.85, blue: 0.45)
    static let waveformInSegmentColor = Color(white: 0.75, opacity: 0.6)

    static let playheadColor = Color.red
    static let bladeLineColor = Color.yellow
    static let silenceThresholdColor = Color(red: 1.0, green: 0.35, blue: 0.35, opacity: 0.8)

    // MARK: - 靜音偵測預設值
    static let defaultSilenceThresholdDB: Float = -20
    static let defaultMinSilenceDuration: Double = 0.5
    static let defaultSilencePadding: Double = 0.1

    // MARK: - 字幕軌
    static let subtitleTrackHeight: CGFloat = 40
    static let subtitleS1Color = Color(red: 0.55, green: 0.35, blue: 0.70)
    static let subtitleS2Color = Color(red: 0.35, green: 0.55, blue: 0.70)
    static let subtitleEntryCornerRadius: CGFloat = 3

    // MARK: - 匯出
    static let defaultExportFilename = "懶人剪輯_輸出.mp4"
    static let exportProgressPollInterval: TimeInterval = 0.1
}
