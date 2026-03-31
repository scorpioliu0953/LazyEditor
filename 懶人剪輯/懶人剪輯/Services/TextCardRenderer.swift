import CoreImage
import CoreGraphics
import AppKit
import SwiftUI

/// 將字卡繪製到 CIImage 上（用於匯出時燒錄）
struct TextCardRenderer {

    struct TrackSnapshot {
        let entries: [CardSnapshot]

        struct CardSnapshot {
            let startTime: Double
            let endTime: Double
            let text: String
            let fontName: String
            let fontSizeRatio: CGFloat
            let fontWeight: NSFont.Weight
            let textColor: NSColor
            let backgroundColor: NSColor
            let cornerRadius: CGFloat
            let strokeColor: NSColor
            let strokeWidth: CGFloat
            let shadowColor: NSColor
            let shadowRadius: CGFloat
            let padding: CGFloat
            let positionX: CGFloat
            let positionY: CGFloat
            let scale: CGFloat
            let widthRatio: CGFloat
        }
    }

    /// 從 TextCardTrack 建立快照（跨 thread 安全）
    static func snapshot(from track: TextCardTrack) -> TrackSnapshot {
        TrackSnapshot(
            entries: track.entries.map { entry in
                let style = entry.style
                return TrackSnapshot.CardSnapshot(
                    startTime: entry.startTime,
                    endTime: entry.endTime,
                    text: entry.text,
                    fontName: style.fontName,
                    fontSizeRatio: style.fontSizeRatio,
                    fontWeight: nsWeight(from: style.fontWeight),
                    textColor: NSColor(style.textColor),
                    backgroundColor: NSColor(style.backgroundColor),
                    cornerRadius: style.cornerRadius,
                    strokeColor: NSColor(style.strokeColor),
                    strokeWidth: style.strokeWidth,
                    shadowColor: NSColor(style.shadowColor),
                    shadowRadius: style.shadowRadius,
                    padding: style.padding,
                    positionX: entry.positionX,
                    positionY: entry.positionY,
                    scale: entry.scale,
                    widthRatio: entry.widthRatio
                )
            }
        )
    }

    /// 在指定時間點將字卡繪製到 CIImage 上
    static func render(
        onto image: CIImage,
        at time: Double,
        renderSize: CGSize,
        track: TrackSnapshot?
    ) -> CIImage {
        guard let track, !track.entries.isEmpty else { return image }

        let activeCards = track.entries.filter { time >= $0.startTime && time < $0.endTime }
        guard !activeCards.isEmpty else { return image }

        let width = Int(renderSize.width)
        let height = Int(renderSize.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx

        let pixelScale = renderSize.height / 400.0

        for card in activeCards {
            drawCard(card, canvasSize: renderSize, pixelScale: pixelScale, context: ctx)
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = ctx.makeImage() else { return image }
        let overlay = CIImage(cgImage: cgImage)
        return overlay.composited(over: image)
    }

    // MARK: - 繪製單張字卡

    private static func drawCard(
        _ card: TrackSnapshot.CardSnapshot,
        canvasSize: CGSize,
        pixelScale: CGFloat,
        context: CGContext
    ) {
        let fontSize = canvasSize.height * card.fontSizeRatio * card.scale
        let scaledPadding = card.padding * card.scale * pixelScale
        let scaledCornerRadius = card.cornerRadius * card.scale * pixelScale
        let scaledStrokeWidth = card.strokeWidth * pixelScale
        let scaledShadowRadius = card.shadowRadius * pixelScale

        let font: NSFont = {
            let descriptor = NSFontDescriptor(fontAttributes: [
                .family: card.fontName
            ]).addingAttributes([
                .traits: [NSFontDescriptor.TraitKey.weight: card.fontWeight]
            ])
            if let f = NSFont(descriptor: descriptor, size: fontSize) {
                return f
            }
            if let f = NSFont(name: card.fontName, size: fontSize) {
                return f
            }
            return NSFont.systemFont(ofSize: fontSize, weight: card.fontWeight)
        }()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        var textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: card.textColor,
            .paragraphStyle: paragraphStyle
        ]

        if card.shadowRadius > 0 {
            let shadow = NSShadow()
            shadow.shadowColor = card.shadowColor
            shadow.shadowBlurRadius = scaledShadowRadius
            shadow.shadowOffset = NSSize(width: 0, height: -pixelScale)
            textAttrs[.shadow] = shadow
        }

        let attrStr = NSAttributedString(string: card.text, attributes: textAttrs)
        let maxWidth = canvasSize.width * card.widthRatio
        let boundingRect = attrStr.boundingRect(
            with: NSSize(width: maxWidth, height: canvasSize.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        // 字卡位置：以 positionX/Y 為中心
        let centerX = canvasSize.width * card.positionX
        let centerY = canvasSize.height * card.positionY
        let textX = centerX - maxWidth / 2
        let textY = centerY - boundingRect.height / 2

        let drawRect = NSRect(x: textX, y: textY, width: maxWidth, height: boundingRect.height + 4)

        // 背景
        if card.backgroundColor.alphaComponent > 0.01 {
            let textWidth = boundingRect.width
            let bgX = centerX - textWidth / 2 - scaledPadding
            let bgRect = NSRect(
                x: bgX,
                y: textY - scaledPadding,
                width: textWidth + scaledPadding * 2,
                height: boundingRect.height + scaledPadding * 2
            )
            context.saveGState()
            context.setFillColor(card.backgroundColor.cgColor)
            let path = CGPath(
                roundedRect: bgRect,
                cornerWidth: scaledCornerRadius,
                cornerHeight: scaledCornerRadius,
                transform: nil
            )
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
        }

        // 描邊
        if scaledStrokeWidth > 0 {
            let nsStrokePercent = (scaledStrokeWidth / fontSize) * 100.0 * 2.0

            context.saveGState()
            context.setLineJoin(.round)
            context.setLineCap(.round)

            let strokeAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: card.strokeColor,
                .strokeColor: card.strokeColor,
                .strokeWidth: -nsStrokePercent,
                .paragraphStyle: paragraphStyle
            ]
            let strokeStr = NSAttributedString(string: card.text, attributes: strokeAttrs)
            strokeStr.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

            context.restoreGState()
        }

        // 主文字
        attrStr.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    // MARK: - Font Weight 轉換

    private static func nsWeight(from weight: SwiftUI.Font.Weight) -> NSFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin:       return .thin
        case .light:      return .light
        case .regular:    return .regular
        case .medium:     return .medium
        case .semibold:   return .semibold
        case .bold:       return .bold
        case .heavy:      return .heavy
        case .black:      return .black
        default:          return .medium
        }
    }
}
