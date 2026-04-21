import Foundation

struct ProjectDocument: Codable {
    var version: Int = 1
    var clips: [ClipDocument] = []
    var segments: [SegmentDocument] = []
    var primarySubtitle: SubtitleTrackDocument?
    var secondarySubtitle: SubtitleTrackDocument?
    var audioSettings: AudioSettingsDocument = .init()
    var silenceConfig: SilenceConfigDocument = .init()
    var textCards: [TextCardEntryDocument]?
    var filterPreset: String = "none"
    var filterIntensity: Float = 1.0
    var playheadPosition: Double = 0
    var zoomScale: Double = 100
}

struct ClipDocument: Codable {
    var id: String
    var bookmark: Data
    var duration: Double
}

struct SegmentDocument: Codable {
    var id: String
    var clipID: String
    var startTime: Double
    var endTime: Double
    var volumeDB: Float
}

struct SubtitleTrackDocument: Codable {
    var entries: [SubtitleEntryDocument]
    var settings: SubtitleSettingsDocument
    var language: String
    var isVisible: Bool
}

struct SubtitleEntryDocument: Codable {
    var id: String
    var startTime: Double
    var endTime: Double
    var text: String
}

struct SubtitleSettingsDocument: Codable {
    var fontName: String = "PingFang TC"
    var fontSizeRatio: Double = 0.055
    var verticalPositionRatio: Double = 0.88
    var strokeWidth: Double = 1.2
    var letterSpacing: Double = 0
}

struct TextCardEntryDocument: Codable {
    var id: String
    var startTime: Double
    var endTime: Double
    var text: String
    var style: String
    var positionX: Double
    var positionY: Double
    var scale: Double
    var widthRatio: Double
    var heightRatio: Double = 0
    var cornerRadius: Double = -1
    var fadeInOut: Bool = false
    var soundEffect: String = "none"
}

struct AudioSettingsDocument: Codable {
    var volumeDB: Float = 0
    var eqEnabled: Bool = false
    var eqPreset: String = "flat"
    var bands: [Float] = [0, 0, 0, 0, 0]
    var noiseReductionEnabled: Bool = false
    var noiseReductionStrength: Float = 0.6
    var levelingEnabled: Bool = false
    var levelingAmount: Float = 0.5
}

struct SilenceConfigDocument: Codable {
    var thresholdDB: Float = -20
    var minDuration: Double = 0.5
    var paddingDuration: Double = 0.1
}
