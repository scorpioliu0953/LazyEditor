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
            let heightRatio: CGFloat
            let effectiveCornerRadius: CGFloat
            let fadeInOut: Bool
            let soundEffect: TextCardSoundEffect
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
                    widthRatio: entry.widthRatio,
                    heightRatio: entry.heightRatio,
                    effectiveCornerRadius: entry.effectiveCornerRadius,
                    fadeInOut: entry.fadeInOut,
                    soundEffect: entry.soundEffect
                )
            }
        )
    }

    /// 渲染字卡覆層（不合成到影片上，用於匯出快取）
    static func renderOverlay(
        at time: Double,
        renderSize: CGSize,
        track: TrackSnapshot?
    ) -> CIImage? {
        guard let track, !track.entries.isEmpty else { return nil }

        let activeCards = track.entries.filter { time >= $0.startTime && time < $0.endTime }
        guard !activeCards.isEmpty else { return nil }

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
        ) else { return nil }

        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx

        let pixelScale = renderSize.height / 400.0

        for card in activeCards {
            drawCard(card, canvasSize: renderSize, pixelScale: pixelScale, context: ctx, time: time)
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }

    /// 在指定時間點將字卡繪製到 CIImage 上
    static func render(
        onto image: CIImage,
        at time: Double,
        renderSize: CGSize,
        track: TrackSnapshot?
    ) -> CIImage {
        guard let overlay = renderOverlay(at: time, renderSize: renderSize, track: track) else {
            return image
        }
        return overlay.composited(over: image)
    }

    // MARK: - 繪製單張字卡

    private static func drawCard(
        _ card: TrackSnapshot.CardSnapshot,
        canvasSize: CGSize,
        pixelScale: CGFloat,
        context: CGContext,
        time: Double
    ) {
        // 淡入淡出 opacity
        if card.fadeInOut {
            let fadeDuration = 0.3
            let elapsed = time - card.startTime
            let remaining = card.endTime - time
            var opacity = 1.0
            if elapsed < fadeDuration { opacity = min(opacity, elapsed / fadeDuration) }
            if remaining < fadeDuration { opacity = min(opacity, remaining / fadeDuration) }
            let alpha = CGFloat(max(0, min(1, opacity)))
            context.saveGState()
            context.setAlpha(alpha)
        }
        let fontSize = canvasSize.height * card.fontSizeRatio * card.scale
        let scaledPadding = card.padding * card.scale * pixelScale
        let scaledCornerRadius = card.effectiveCornerRadius * card.scale * pixelScale
        let scaledStrokeWidth = card.strokeWidth * card.scale * pixelScale
        let scaledShadowRadius = card.shadowRadius * pixelScale

        // 字型查找：先嘗試 PostScript 名稱（FontPicker 存的格式），再用 family name fallback
        let font: NSFont = {
            if let f = NSFont(name: card.fontName, size: fontSize) {
                return f
            }
            let descriptor = NSFontDescriptor(fontAttributes: [
                .family: card.fontName
            ]).addingAttributes([
                .traits: [NSFontDescriptor.TraitKey.weight: card.fontWeight]
            ])
            if let f = NSFont(descriptor: descriptor, size: fontSize) {
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

        let drawHeight: CGFloat
        if card.heightRatio > 0 {
            drawHeight = canvasSize.height * card.heightRatio
        } else {
            drawHeight = boundingRect.height + 4
        }

        // 字卡位置：以 positionX/Y 為中心
        let centerX = canvasSize.width * card.positionX
        let centerY = canvasSize.height * card.positionY
        let textX = centerX - maxWidth / 2
        let textY = centerY - drawHeight / 2

        let drawRect = NSRect(x: textX, y: textY, width: maxWidth, height: drawHeight)

        // 背景
        if card.backgroundColor.alphaComponent > 0.01 {
            let textWidth = maxWidth
            let bgX = centerX - textWidth / 2 - scaledPadding
            let bgRect = NSRect(
                x: bgX,
                y: textY - scaledPadding,
                width: textWidth + scaledPadding * 2,
                height: drawHeight + scaledPadding * 2
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

        // 描邊（nsStrokePercent 負值描邊）
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

        if card.fadeInOut {
            context.restoreGState()
        }
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
