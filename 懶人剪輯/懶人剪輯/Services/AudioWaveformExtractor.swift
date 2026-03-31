import AVFoundation

struct AudioWaveformExtractor {
    nonisolated static func extractWaveform(from asset: AVURLAsset) async throws -> [Float] {
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            return []
        }

        let reader = try AVAssetReader(asset: asset)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: Constants.waveformSampleRate,
            AVNumberOfChannelsKey: 1
        ]

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else {
            throw WaveformError.readerFailed(reader.error)
        }

        var allSamples: [Float] = []
        allSamples.reserveCapacity(Int(Constants.waveformSampleRate) * 600) // 預留 10 分鐘

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            var lengthAtOffset: Int = 0
            var totalLength: Int = 0
            var dataPointer: UnsafeMutablePointer<Int8>?

            let status = CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: &lengthAtOffset,
                totalLengthOut: &totalLength,
                dataPointerOut: &dataPointer
            )

            guard status == noErr, let ptr = dataPointer else { continue }

            let floatCount = totalLength / MemoryLayout<Float>.size
            let floatPtr = UnsafeRawPointer(ptr).bindMemory(to: Float.self, capacity: floatCount)
            let buffer = UnsafeBufferPointer(start: floatPtr, count: floatCount)

            allSamples.append(contentsOf: buffer)
        }

        guard reader.status == .completed else {
            throw WaveformError.readerFailed(reader.error)
        }

        // 每 bin 取峰值
        let samplesPerBin = Constants.waveformSamplesPerBin
        let binCount = allSamples.count / samplesPerBin
        guard binCount > 0 else { return [] }

        var peaks = [Float](repeating: 0, count: binCount)
        for i in 0..<binCount {
            let start = i * samplesPerBin
            let end = min(start + samplesPerBin, allSamples.count)
            var maxVal: Float = 0
            for j in start..<end {
                let absVal = abs(allSamples[j])
                if absVal > maxVal { maxVal = absVal }
            }
            peaks[i] = maxVal
        }

        // 正規化
        let globalMax = peaks.max() ?? 1.0
        if globalMax > 0 {
            for i in 0..<peaks.count {
                peaks[i] /= globalMax
            }
        }

        return peaks
    }

    enum WaveformError: Error, LocalizedError {
        case readerFailed(Error?)

        var errorDescription: String? {
            switch self {
            case .readerFailed(let err):
                "無法讀取音軌：\(err?.localizedDescription ?? "未知錯誤")"
            }
        }
    }
}
