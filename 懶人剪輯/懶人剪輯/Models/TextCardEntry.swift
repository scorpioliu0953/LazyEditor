import Foundation
import SwiftUI

struct TextCardEntry: Identifiable {
    let id: UUID
    var startTime: Double
    var endTime: Double
    var text: String
    var style: TextCardStyle
    var positionX: CGFloat  // 0~1 ratio (水平位置)
    var positionY: CGFloat  // 0~1 ratio (垂直位置)
    var scale: CGFloat      // 縮放比例（1.0 = 原始大小）
    var widthRatio: CGFloat // 卡片寬度佔畫面比例

    var duration: Double { endTime - startTime }

    init(
        id: UUID = UUID(),
        startTime: Double,
        endTime: Double,
        text: String,
        style: TextCardStyle = .simpleTitle,
        positionX: CGFloat = 0.5,
        positionY: CGFloat = 0.5,
        scale: CGFloat = 1.0,
        widthRatio: CGFloat = 0.4
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
    }
}
