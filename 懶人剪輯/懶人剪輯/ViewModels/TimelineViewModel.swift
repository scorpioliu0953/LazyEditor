import Foundation
import Observation

@Observable
final class TimelineViewModel {
    var zoomScale: CGFloat = Constants.defaultPixelsPerSecond
    var scrollOffset: CGFloat = 0

    /// 剪刀工具懸停時的 X 座標（相對於時間軸內容區域），nil 表示未懸停
    var bladeHoverX: CGFloat?

    /// 時間（秒）→ 畫素 X 座標
    func timeToX(_ time: Double) -> CGFloat {
        CGFloat(time) * zoomScale
    }

    /// 畫素 X 座標 → 時間（秒）
    func xToTime(_ x: CGFloat) -> Double {
        Double(x / zoomScale)
    }

    /// 計算片段寬度（畫素）
    func segmentWidth(duration: Double) -> CGFloat {
        CGFloat(duration) * zoomScale
    }

    /// 計算片段對應的波形樣本範圍
    func waveformSampleRange(for segment: ClipSegment) -> Range<Int> {
        let bps = Constants.waveformBinsPerSecond
        let start = Int(segment.startTime * Double(bps))
        let end = Int(segment.endTime * Double(bps))
        return start..<end
    }

    /// 計算時間軸總內容寬度
    func totalContentWidth(segments: [ClipSegment]) -> CGFloat {
        let totalDuration = segments.reduce(0.0) { $0 + $1.duration }
        return CGFloat(totalDuration) * zoomScale + CGFloat(max(0, segments.count - 1)) * Constants.segmentSpacing
    }

    func clampZoom() {
        zoomScale = max(Constants.minPixelsPerSecond, min(Constants.maxPixelsPerSecond, zoomScale))
    }
}
