import SwiftUI

struct SubtitleOverlayView: View {
    let vm: ProjectViewModel

    var body: some View {
        GeometryReader { geo in
            let currentTime = vm.playback.currentTime
            let hasPrimary = vm.primarySubtitleTrack.isVisible
            let hasSecondary = vm.secondarySubtitleTrack.isVisible
            let primaryEntry = vm.primarySubtitleTrack.activeEntry(at: currentTime)
            let secondaryEntry = vm.secondarySubtitleTrack.activeEntry(at: currentTime)
            let isBilingual = hasPrimary && hasSecondary
                && !vm.primarySubtitleTrack.entries.isEmpty
                && !vm.secondarySubtitleTrack.entries.isEmpty

            ZStack {
                // 第一語言字幕
                if hasPrimary, let entry = primaryEntry {
                    let settings = vm.primarySubtitleTrack.settings
                    let yRatio: CGFloat = settings.verticalPositionRatio

                    subtitleText(
                        text: entry.text,
                        settings: settings,
                        fontSize: geo.size.height * settings.fontSizeRatio,
                        maxWidth: geo.size.width * 0.9
                    )
                    .position(x: geo.size.width / 2, y: geo.size.height * yRatio)
                }

                // 第二語言字幕
                if hasSecondary, let entry = secondaryEntry, isBilingual {
                    let settings = vm.secondarySubtitleTrack.settings

                    subtitleText(
                        text: entry.text,
                        settings: settings,
                        fontSize: geo.size.height * settings.fontSizeRatio,
                        maxWidth: geo.size.width * 0.9
                    )
                    .position(x: geo.size.width / 2, y: geo.size.height * settings.verticalPositionRatio)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func subtitleText(
        text: String,
        settings: SubtitleSettings,
        fontSize: CGFloat,
        maxWidth: CGFloat
    ) -> some View {
        // 使用 ZStack 確保只有單層文字渲染，避免半透明問題
        ZStack {
            // 描邊層（在主文字之下）
            if settings.strokeWidth > 0 {
                let sw = settings.strokeWidth
                // 8 方向描邊（含對角線，完整覆蓋）
                let offsets: [(CGFloat, CGFloat)] = [
                    (sw, 0), (-sw, 0), (0, sw), (0, -sw),
                    (sw * 0.7, sw * 0.7), (-sw * 0.7, sw * 0.7),
                    (sw * 0.7, -sw * 0.7), (-sw * 0.7, -sw * 0.7)
                ]
                ForEach(0..<offsets.count, id: \.self) { i in
                    Text(text)
                        .font(.custom(settings.fontName, size: fontSize))
                        .fontWeight(settings.fontWeight)
                        .foregroundStyle(settings.strokeColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: maxWidth)
                        .offset(x: offsets[i].0, y: offsets[i].1)
                }
            }

            // 主文字（最上層，唯一一層前景色）
            Text(text)
                .font(.custom(settings.fontName, size: fontSize))
                .fontWeight(settings.fontWeight)
                .foregroundStyle(settings.textColor)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: maxWidth)
        }
        .padding(settings.backgroundPadding)
        .background(
            settings.backgroundColor != .clear
                ? RoundedRectangle(cornerRadius: 4)
                    .fill(settings.backgroundColor)
                : nil
        )
        .shadow(color: settings.shadowColor, radius: settings.shadowRadius)
    }
}
