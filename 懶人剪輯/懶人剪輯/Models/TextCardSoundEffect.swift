import Foundation

enum TextCardSoundEffect: String, CaseIterable, Codable, Identifiable {
    case none
    case pop
    case ding
    case whoosh
    case click
    case chime
    case bubble
    case swoosh
    case bell
    case tap
    case tone

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:    "無"
        case .pop:     "Pop"
        case .ding:    "Ding"
        case .whoosh:  "Whoosh"
        case .click:   "Click"
        case .chime:   "Chime"
        case .bubble:  "Bubble"
        case .swoosh:  "Swoosh"
        case .bell:    "Bell"
        case .tap:     "Tap"
        case .tone:    "Tone"
        }
    }
}
