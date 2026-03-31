import SwiftUI

enum TextCardStyle: String, CaseIterable, Identifiable, Codable {
    case simpleTitle
    case boldTitle
    case lowerThird
    case speechBubble
    case highlight
    case handwritten
    case newsBanner
    case socialTag
    case chapterTitle
    case warningAlert

    var id: String { rawValue }

    var label: String {
        switch self {
        case .simpleTitle:   "簡潔標題"
        case .boldTitle:     "粗體標題"
        case .lowerThird:    "下方字條"
        case .speechBubble:  "對話泡泡"
        case .highlight:     "螢光標記"
        case .handwritten:   "手寫風格"
        case .newsBanner:    "新聞橫幅"
        case .socialTag:     "社群標籤"
        case .chapterTitle:  "章節標題"
        case .warningAlert:  "警告提示"
        }
    }

    var fontName: String {
        switch self {
        case .handwritten:   "Noteworthy"
        case .newsBanner:    "Helvetica Neue"
        case .chapterTitle:  "Georgia"
        default:             "PingFang TC"
        }
    }

    var fontSizeRatio: CGFloat {
        switch self {
        case .boldTitle:     0.07
        case .chapterTitle:  0.065
        case .lowerThird:    0.04
        case .newsBanner:    0.04
        case .socialTag:     0.035
        case .warningAlert:  0.05
        default:             0.05
        }
    }

    var fontWeight: Font.Weight {
        switch self {
        case .boldTitle:     .heavy
        case .warningAlert:  .bold
        case .newsBanner:    .semibold
        case .chapterTitle:  .semibold
        case .highlight:     .semibold
        default:             .medium
        }
    }

    var textColor: Color {
        switch self {
        case .highlight:     .black
        case .warningAlert:  .white
        case .newsBanner:    .white
        case .socialTag:     .white
        default:             .white
        }
    }

    var backgroundColor: Color {
        switch self {
        case .simpleTitle:   .clear
        case .boldTitle:     .clear
        case .lowerThird:    Color(white: 0.1, opacity: 0.85)
        case .speechBubble:  .white
        case .highlight:     Color(red: 1.0, green: 0.95, blue: 0.2, opacity: 0.9)
        case .handwritten:   .clear
        case .newsBanner:    Color(red: 0.8, green: 0.15, blue: 0.15, opacity: 0.95)
        case .socialTag:     Color(red: 0.2, green: 0.6, blue: 1.0, opacity: 0.9)
        case .chapterTitle:  Color(white: 0.0, opacity: 0.6)
        case .warningAlert:  Color(red: 0.9, green: 0.3, blue: 0.1, opacity: 0.95)
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .speechBubble:  16
        case .socialTag:     14
        case .warningAlert:  8
        case .highlight:     4
        case .newsBanner:    0
        case .lowerThird:    4
        case .chapterTitle:  2
        default:             6
        }
    }

    var strokeColor: Color {
        switch self {
        case .simpleTitle:   .black.opacity(0.9)
        case .boldTitle:     .black
        case .handwritten:   .black.opacity(0.7)
        case .speechBubble:  Color(white: 0.3)
        default:             .clear
        }
    }

    var strokeWidth: CGFloat {
        switch self {
        case .simpleTitle:   1.0
        case .boldTitle:     2.0
        case .handwritten:   0.8
        case .speechBubble:  1.5
        default:             0
        }
    }

    var shadowColor: Color {
        switch self {
        case .boldTitle:     .black.opacity(0.6)
        case .speechBubble:  .black.opacity(0.3)
        case .chapterTitle:  .black.opacity(0.5)
        default:             .clear
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .boldTitle:     4
        case .speechBubble:  6
        case .chapterTitle:  3
        default:             0
        }
    }

    var padding: CGFloat {
        switch self {
        case .simpleTitle:   6
        case .boldTitle:     8
        case .lowerThird:    10
        case .speechBubble:  14
        case .highlight:     6
        case .handwritten:   4
        case .newsBanner:    10
        case .socialTag:     10
        case .chapterTitle:  12
        case .warningAlert:  10
        }
    }
}
