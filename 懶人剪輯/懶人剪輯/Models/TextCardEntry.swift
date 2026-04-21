import Foundation
import SwiftUI

struct TextCardEntry: Identifiable, Equatable {
    let id: UUID
    var startTime: Double
    var endTime: Double
    var text: String
    var style: TextCardStyle
    var positionX: CGFloat  // 0~1 ratio (水平位置)
    var positionY: CGFloat  // 0~1 ratio (垂直位置)
    var scale: CGFloat      // 縮放比例（1.0 = 原始大小）
    var widthRatio: CGFloat // 卡片寬度佔畫面比例
    var heightRatio: CGFloat // 卡片高度佔畫面比例（0 = 自動高度）
    var cornerRadius: CGFloat // 圓角半徑（-1 = 使用樣式預設值）
    var fadeInOut: Bool       // 淡入淡出效果
    var soundEffect: TextCardSoundEffect // 出現時音效

    var duration: Double { endTime - startTime }

    /// 實際使用的圓角半徑（-1 時取樣式預設值）
    var effectiveCornerRadius: CGFloat {
        cornerRadius >= 0 ? cornerRadius : style.cornerRadius
    }

    init(
        id: UUID = UUID(),
        startTime: Double,
        endTime: Double,
        text: String,
        style: TextCardStyle = .simpleTitle,
        positionX: CGFloat = 0.5,
        positionY: CGFloat = 0.5,
        scale: CGFloat = 1.0,
        widthRatio: CGFloat = 0.4,
        heightRatio: CGFloat = 0,
        cornerRadius: CGFloat = -1,
        fadeInOut: Bool = false,
        soundEffect: TextCardSoundEffect = .none
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.style = style
        self.positionX = positionX
        self.positionY = positionY
        self.scale = scale
        self.widthRatio = widthRatio
        self.heightRatio = heightRatio
        self.cornerRadius = cornerRadius
        self.fadeInOut = fadeInOut
        self.soundEffect = soundEffect
    }
}
