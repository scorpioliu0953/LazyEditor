import SwiftUI

struct WaveformView: View {
    let samples: ArraySlice<Float>
    var color: Color = Constants.waveformColor
    /// 靜音閾值線性值（0~1），nil 則不顯示
    var silenceThreshold: Float? = nil

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let midY = size.height / 2
            let threshold = silenceThreshold

            // 降採樣：bar 數量不超過可用像素寬度，避免繪製數千條不可見的線段
            let maxBars = max(1, Int(size.width))
            let barCount = min(samples.count, maxBars)
            let samplesPerBar = max(1, samples.count / barCount)
            let barWidth = size.width / CGFloat(barCount)

            var path = Path()
            for barIdx in 0..<barCount {
                let rangeStart = samples.startIndex + barIdx * samplesPerBar
                let rangeEnd = min(rangeStart + samplesPerBar, samples.endIndex)
                // 取該組峰值，保留波形視覺特徵
                var peak: Float = 0
                for i in rangeStart..<rangeEnd {
                    let v = samples[i]
                    if v > peak { peak = v }
                }
                let x = CGFloat(barIdx) * barWidth + barWidth / 2
                let amplitude = CGFloat(peak) * midY
                path.move(to: CGPoint(x: x, y: midY - amplitude))
                path.addLine(to: CGPoint(x: x, y: midY + amplitude))
            }
            context.stroke(path, with: .color(color), lineWidth: max(1, barWidth * 0.8))

            // 繪製靜音閾值線
            if let threshold {
                let thresholdY = CGFloat(threshold) * midY
                var threshLine = Path()
                threshLine.move(to: CGPoint(x: 0, y: midY - thresholdY))
                threshLine.addLine(to: CGPoint(x: size.width, y: midY - thresholdY))
                threshLine.move(to: CGPoint(x: 0, y: midY + thresholdY))
                threshLine.addLine(to: CGPoint(x: size.width, y: midY + thresholdY))

                context.stroke(
                    threshLine,
                    with: .color(Constants.silenceThresholdColor),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )

                var silenceArea = Path()
                silenceArea.addRect(CGRect(
                    x: 0, y: midY - thresholdY,
                    width: size.width, height: thresholdY * 2
                ))
                context.fill(silenceArea, with: .color(Constants.silenceThresholdColor.opacity(0.08)))
            }
        }
    }
}
