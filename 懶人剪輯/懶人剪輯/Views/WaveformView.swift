import SwiftUI

struct WaveformView: View {
    let samples: [Float]
    var color: Color = Constants.waveformColor
    /// 靜音閾值線性值（0~1），nil 則不顯示
    var silenceThreshold: Float? = nil

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let midY = size.height / 2
            let sampleWidth = size.width / CGFloat(samples.count)
            let threshold = silenceThreshold

            // 繪製波形
            var path = Path()
            for (i, sample) in samples.enumerated() {
                let x = CGFloat(i) * sampleWidth + sampleWidth / 2
                let amplitude = CGFloat(sample) * midY
                path.move(to: CGPoint(x: x, y: midY - amplitude))
                path.addLine(to: CGPoint(x: x, y: midY + amplitude))
            }
            context.stroke(path, with: .color(color), lineWidth: max(1, sampleWidth * 0.8))

            // 繪製靜音閾值線
            if let threshold {
                let thresholdY = CGFloat(threshold) * midY
                var threshLine = Path()
                // 上方線
                threshLine.move(to: CGPoint(x: 0, y: midY - thresholdY))
                threshLine.addLine(to: CGPoint(x: size.width, y: midY - thresholdY))
                // 下方線
                threshLine.move(to: CGPoint(x: 0, y: midY + thresholdY))
                threshLine.addLine(to: CGPoint(x: size.width, y: midY + thresholdY))

                context.stroke(
                    threshLine,
                    with: .color(Constants.silenceThresholdColor),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )

                // 填充靜音區域（閾值內）
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
