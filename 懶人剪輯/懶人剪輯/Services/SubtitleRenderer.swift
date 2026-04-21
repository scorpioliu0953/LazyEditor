import CoreImage
import CoreGraphics
import AppKit
import SwiftUI

/// 將字幕文字繪製到 CIImage 上（用於匯出時燒錄字幕）
struct SubtitleRenderer {

    struct TrackSnapshot {
        let entries: [SubtitleEntry]
        let fontName: String
        let fontSizeRatio: CGFloat
        let fontWeight: NSFont.Weight
        let textColor: NSColor
        let strokeColor: NSColor
        let strokeWidth: CGFloat
        let shadowColor: NSColor
        let shadowRadius: CGFloat
        let backgroundColor: NSColor
        let backgroundPadding: CGFloat
        let verticalPositionRatio: CGFloat
        let letterSpacing: CGFloat
        let isVisible: Bool
    }

    /// 從 SubtitleTrack 建立快照（跨 thread 安全）
    static func snapshot(from track: SubtitleTrack) -> TrackSnapshot {
        TrackSnapshot(
            entries: track.entries,
            fontName: track.settings.fontName,
            fontSizeRatio: track.settings.fontSizeRatio,
            fontWeight: nsWeight(from: track.settings.fontWeight),
            textColor: NSColor(track.settings.textColor),
            strokeColor: NSColor(track.settings.strokeColor),
            strokeWidth: track.settings.strokeWidth,
            shadowColor: NSColor(track.settings.shadowColor),
            shadowRadius: track.settings.shadowRadius,
            backgroundColor: NSColor(track.settings.backgroundColor),
            backgroundPadding: track.settings.backgroundPadding,
            verticalPositionRatio: track.settings.verticalPositionRatio,
            letterSpacing: track.settings.letterSpacing,
            isVisible: track.isVisible
        )
    }

    /// 渲染字幕覆層（不合成到影片上，用於匯出快取）
    static func renderOverlay(
        at time: Double,
        renderSize: CGSize,
        primaryTrack: TrackSnapshot?,
        secondaryTrack: TrackSnapshot?
    ) -> CIImage? {
        let hasPrimary = primaryTrack?.isVisible == true && !(primaryTrack?.entries.isEmpty ?? true)
        let hasSecondary = secondaryTrack?.isVisible == true && !(secondaryTrack?.entries.isEmpty ?? true)

        guard hasPrimary || hasSecondary else { return nil }

        let primaryEntry = primaryTrack?.entries.first { time >= $0.startTime && time < $0.endTime }
        let secondaryEntry = secondaryTrack?.entries.first { time >= $0.startTime && time < $0.endTime }

        guard primaryEntry != nil || secondaryEntry != nil else { return nil }

        let isBilingual = hasPrimary && hasSecondary

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

        if let track = primaryTrack, let entry = primaryEntry {
            drawSubtitleText(
                text: entry.text,
                track: track,
                fontSize: renderSize.height * track.fontSizeRatio,
                yRatio: track.verticalPositionRatio,
                canvasSize: renderSize,
                context: ctx
            )
        }

        if isBilingual, let track = secondaryTrack, let entry = secondaryEntry {
            drawSubtitleText(
                text: entry.text,
                track: track,
                fontSize: renderSize.height * track.fontSizeRatio,
                yRatio: track.verticalPositionRatio,
                canvasSize: renderSize,
                context: ctx
            )
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }

    /// 在指定時間點將字幕繪製到 CIImage 上
    static func render(
        onto image: CIImage,
        at time: Double,
        renderSize: CGSize,
        primaryTrack: TrackSnapshot?,
        secondaryTrack: TrackSnapshot?
    ) -> CIImage {
        guard let overlay = renderOverlay(
            at: time,
            renderSize: renderSize,
            primaryTrack: primaryTrack,
            secondaryTrack: secondaryTrack
        ) else {
            return image
        }
        return overlay.composited(over: image)
    }

    // MARK: - 文字繪製

    private static func drawSubtitleText(
        text: String,
        track: TrackSnapshot,
        fontSize: CGFloat,
        yRatio: CGFloat,
        canvasSize: CGSize,
        context: CGContext
    ) {
        // 字型查找：先嘗試 PostScript 名稱（FontPicker 存的格式），再用 family name fallback
        let font: NSFont = {
            // 1) 嘗試直接以 PostScript 名稱建立（如 PingFangTC-Semibold）
            if let f = NSFont(name: track.fontName, size: fontSize) {
                return f
            }
            // 2) 以 family name + weight 建立（如 "PingFang TC"）
            let descriptor = NSFontDescriptor(fontAttributes: [
                .family: track.fontName
            ]).addingAttributes([
                .traits: [NSFontDescriptor.TraitKey.weight: track.fontWeight]
            ])
            if let f = NSFont(descriptor: descriptor, size: fontSize) {
                return f
            }
            return NSFont.systemFont(ofSize: fontSize, weight: track.fontWeight)
        }()

        // 預覽中的樣式值（strokeWidth、padding、shadowRadius）是以 ~400pt 高的預覽區域為基準
        // 匯出時需要等比縮放到實際影片解析度
        let pixelScale = canvasSize.height / 400.0
        let scaledStrokeWidth = track.strokeWidth * pixelScale
        let scaledPadding = track.backgroundPadding * pixelScale
        let scaledShadowRadius = track.shadowRadius * pixelScale
        let scaledCornerRadius = 4.0 * pixelScale

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        // 主文字屬性（不含描邊，描邊用偏移繪製）
        var textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: track.textColor,
            .paragraphStyle: paragraphStyle
        ]

        // 文字間距
        if track.letterSpacing > 0 {
            textAttrs[.kern] = track.letterSpacing * pixelScale
        }

        // 陰影
        if track.shadowRadius > 0 {
            let shadow = NSShadow()
            shadow.shadowColor = track.shadowColor
            shadow.shadowBlurRadius = scaledShadowRadius
            shadow.shadowOffset = NSSize(width: 0, height: -pixelScale)
            textAttrs[.shadow] = shadow
        }

        let attrStr = NSAttributedString(string: text, attributes: textAttrs)
        let maxWidth = canvasSize.width * 0.9
        let boundingRect = attrStr.boundingRect(
            with: NSSize(width: maxWidth, height: canvasSize.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        // 置中：以 maxWidth 居中（paragraphStyle .center 會在 rect 內置中文字）
        let x = (canvasSize.width - maxWidth) / 2
        let y = canvasSize.height * yRatio - boundingRect.height / 2
        let drawRect = NSRect(x: x, y: y, width: maxWidth, height: boundingRect.height + 4)

        // 背景框（以實際文字寬度為基準）
        if scaledPadding > 0 {
            let textWidth = boundingRect.width
            let bgX = (canvasSize.width - textWidth) / 2 - scaledPadding
            let bgRect = NSRect(
                x: bgX,
                y: y - scaledPadding,
                width: textWidth + scaledPadding * 2,
                height: boundingRect.height + scaledPadding * 2
            )
            context.saveGState()
            context.setFillColor(track.backgroundColor.cgColor)
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
            var strokeAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: track.strokeColor,
                .strokeColor: track.strokeColor,
                .strokeWidth: -nsStrokePercent,
                .paragraphStyle: paragraphStyle
            ]
            if track.letterSpacing > 0 {
                strokeAttrs[.kern] = track.letterSpacing * pixelScale
            }
            let strokeStr = NSAttributedString(string: text, attributes: strokeAttrs)
            strokeStr.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
            context.restoreGState()
        }

        // 繪製主文字（填充層，覆蓋在描邊之上）
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
