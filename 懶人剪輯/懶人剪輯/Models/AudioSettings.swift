import Foundation

@Observable
final class AudioSettings {
    /// 整體音量增益（dB），-20 到 +20
    var volumeDB: Float = 0

    // MARK: - EQ

    var eqEnabled: Bool = false
    var eqPreset: EQPreset = .flat
    /// 5 頻段增益（dB），對應 80Hz / 250Hz / 1kHz / 4kHz / 12kHz
    var bands: [Float] = [0, 0, 0, 0, 0]

    // MARK: - 去雜音

    var noiseReductionEnabled: Bool = false
    /// 去雜音強度 0~1
    var noiseReductionStrength: Float = 0.6

    // MARK: - 音量平衡

    var levelingEnabled: Bool = false
    /// 平衡強度 0~1（越高壓縮越強）
    var levelingAmount: Float = 0.5

    // MARK: - 計算屬性

    var linearVolume: Float {
        powf(10.0, volumeDB / 20.0)
    }

    var hasProcessing: Bool {
        eqEnabled || noiseReductionEnabled || levelingEnabled
    }

    func applyPreset(_ preset: EQPreset) {
        eqPreset = preset
        if preset != .custom {
            bands = preset.bandGains
        }
        eqEnabled = preset != .flat
    }

    /// 是否有任何音頻設定變更（包含音量）
    var hasAnyChange: Bool {
        volumeDB != 0 || hasProcessing
    }

    /// 建立可跨 actor 傳遞的快照
    func snapshot() -> AudioSettingsSnapshot {
        AudioSettingsSnapshot(
            volumeDB: volumeDB,
            linearVolume: linearVolume,
            eqEnabled: eqEnabled,
            bands: bands,
            noiseReductionEnabled: noiseReductionEnabled,
            noiseReductionStrength: noiseReductionStrength,
            levelingEnabled: levelingEnabled,
            levelingAmount: levelingAmount
        )
    }

    nonisolated static let bandFrequencies: [Float] = [80, 250, 1000, 4000, 12000]
    nonisolated static let bandLabels: [String] = ["80", "250", "1k", "4k", "12k"]
}

// MARK: - Sendable 快照（用於背景音頻處理）

struct AudioSettingsSnapshot: Sendable {
    let volumeDB: Float
    let linearVolume: Float
    let eqEnabled: Bool
    let bands: [Float]
    let noiseReductionEnabled: Bool
    let noiseReductionStrength: Float
    let levelingEnabled: Bool
    let levelingAmount: Float

    var hasProcessing: Bool {
        eqEnabled || noiseReductionEnabled || levelingEnabled
    }
}

// MARK: - EQ 預設值

enum EQPreset: String, CaseIterable, Identifiable {
    case flat
    case vlogOutdoor
    case vlogIndoor
    case indoorFix
    case phoneFix
    case broadcast
    case podcast
    case cinematic
    case tutorial
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flat:        "原始"
        case .vlogOutdoor: "Vlog 戶外"
        case .vlogIndoor:  "Vlog 室內"
        case .indoorFix:   "室內錄音修復"
        case .phoneFix:    "手機收音增強"
        case .broadcast:   "廣播人聲"
        case .podcast:     "Podcast"
        case .cinematic:   "電影感"
        case .tutorial:    "教學講解"
        case .custom:      "自訂"
        }
    }

    var description: String {
        switch self {
        case .flat:        "不做任何 EQ 調整"
        case .vlogOutdoor: "削減風聲低頻、大幅提升人聲清晰度"
        case .vlogIndoor:  "減少室內迴響悶感、增加臨場感"
        case .indoorFix:   "修復空間箱體感、移除混濁低頻"
        case .phoneFix:    "補償手機麥克風的薄弱低頻與細節"
        case .broadcast:   "強力低切 + 高頻提亮，接近廣播品質"
        case .podcast:     "溫暖中頻 + 清晰高頻，適合對談節目"
        case .cinematic:   "厚實低頻 + 空氣感高頻，營造影片質感"
        case .tutorial:    "最大化語音清晰度，適合講解與教學"
        case .custom:      "手動調整各頻段"
        }
    }

    /// 5 頻段增益（dB）：80Hz(低架) / 250Hz / 1kHz / 4kHz / 12kHz(高架)
    var bandGains: [Float] {
        switch self {
        //                    80     250    1k     4k     12k
        case .flat:        [  0,     0,     0,     0,     0  ]
        case .vlogOutdoor: [-10,    -4,    +5,   +10,    +4 ]
        case .vlogIndoor:  [ -6,    -3,    +4,    +9,    +5 ]
        case .indoorFix:   [ -8,    -6,    +4,    +8,    +4 ]
        case .phoneFix:    [ +6,    +4,    +3,    +8,    +4 ]
        case .broadcast:   [-12,    +3,    +5,   +11,    +6 ]
        case .podcast:     [ -5,    +2,    +6,    +9,    +5 ]
        case .cinematic:   [ +8,    +4,     0,    +4,    +6 ]
        case .tutorial:    [ -9,    -4,    +7,   +11,    +4 ]
        case .custom:      [  0,     0,     0,     0,     0 ]
        }
    }
}
