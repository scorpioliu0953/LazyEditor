import SwiftUI

struct ClipSegmentView: View {
    let segment: ClipSegment
    let clipName: String
    let waveformData: [Float]?
    let isSelected: Bool
    let width: CGFloat
    let sampleRange: Range<Int>

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Constants.segmentCornerRadius)
                .fill(Constants.segmentFill)

            // 片段內嵌小波形
            if let waveform = waveformSamples {
                WaveformView(samples: waveform, color: Constants.waveformInSegmentColor)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
            }

            // 片段名稱
            Text(clipName)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.top, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if isSelected {
                RoundedRectangle(cornerRadius: Constants.segmentCornerRadius)
                    .strokeBorder(Constants.segmentSelectedBorder, lineWidth: 2)
            }
        }
        .frame(width: width, height: Constants.segmentTrackHeight)
        .clipped()
    }

    private var waveformSamples: ArraySlice<Float>? {
        guard let data = waveformData else { return nil }
        let start = max(0, sampleRange.lowerBound)
        let end = min(data.count, sampleRange.upperBound)
        guard start < end else { return nil }
        return data[start..<end]
    }
}
