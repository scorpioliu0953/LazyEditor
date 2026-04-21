import SwiftUI
import Observation

@Observable
final class SubtitleSettings {
    var fontName: String = "PingFang TC"
    var fontSizeRatio: CGFloat = 0.055
    var fontWeight: Font.Weight = .medium
    var textColor: Color = .white
    var strokeColor: Color = .black.opacity(0.9)
    var strokeWidth: CGFloat = 1.2
    var shadowColor: Color = .clear
    var shadowRadius: CGFloat = 0
    var backgroundColor: Color = .clear
    var backgroundPadding: CGFloat = 0
    var verticalPositionRatio: CGFloat = 0.88
    var letterSpacing: CGFloat = 0

    func applyPreset(_ preset: SubtitleStylePreset) {
        fontName = preset.fontName
        fontWeight = preset.fontWeight
        textColor = preset.textColor
        strokeColor = preset.strokeColor
        strokeWidth = preset.strokeWidth
        shadowColor = preset.shadowColor
        shadowRadius = preset.shadowRadius
        backgroundColor = preset.backgroundColor
        backgroundPadding = preset.backgroundPadding
    }
}
