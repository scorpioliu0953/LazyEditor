import SwiftUI

enum SubtitleStylePreset: String, CaseIterable, Identifiable {
    case cleanWhite
    case netflix
    case youtube
    case boldContrast
    case cinematic
    case modernMinimal
    case newsTicker
    case gameGlow
    case retroVHS
    case elegantSerif

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cleanWhite:    "簡潔白字"
        case .netflix:       "Netflix 風格"
        case .youtube:       "YouTube 字幕"
        case .boldContrast:  "粗體撞色"
        case .cinematic:     "電影質感"
        case .modernMinimal: "現代極簡"
        case .newsTicker:    "新聞跑馬燈"
        case .gameGlow:      "遊戲發光"
        case .retroVHS:      "復古 VHS"
        case .elegantSerif:  "典雅襯線"
        }
    }

    var fontName: String {
        switch self {
        case .elegantSerif:  "Georgia"
        case .retroVHS:      "Courier"
        default:             "PingFang TC"
        }
    }

    var fontWeight: Font.Weight {
        switch self {
        case .boldContrast:  .heavy
        case .netflix:       .bold
        case .newsTicker:    .semibold
        default:             .medium
        }
    }

    var textColor: Color {
        switch self {
        case .boldContrast:  Color.yellow
        case .retroVHS:      Color(red: 1.0, green: 0.96, blue: 0.8)
        default:             .white
        }
    }

    var strokeColor: Color {
        switch self {
        case .cleanWhite:    .black.opacity(0.9)
        case .boldContrast:  .black
        case .retroVHS:      .black.opacity(0.8)
        case .elegantSerif:  .black.opacity(0.7)
        default:             .clear
        }
    }

    var strokeWidth: CGFloat {
        switch self {
        case .cleanWhite:    1.2
        case .boldContrast:  2.5
        case .retroVHS:      1.0
        case .elegantSerif:  0.8
        default:             0
        }
    }

    var shadowColor: Color {
        switch self {
        case .netflix:       .black.opacity(0.8)
        case .cinematic:     .black.opacity(0.5)
        case .modernMinimal: .black.opacity(0.3)
        case .gameGlow:      Color(red: 0.2, green: 0.5, blue: 1.0).opacity(0.8)
        default:             .clear
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .netflix:       4
        case .cinematic:     3
        case .modernMinimal: 2
        case .gameGlow:      8
        default:             0
        }
    }

    var backgroundColor: Color {
        switch self {
        case .youtube:     .black.opacity(0.6)
        case .newsTicker:  Color(red: 0.15, green: 0.15, blue: 0.15, opacity: 0.85)
        default:           .clear
        }
    }

    var backgroundPadding: CGFloat {
        switch self {
        case .youtube:     6
        case .newsTicker:  8
        default:           0
        }
    }
}
