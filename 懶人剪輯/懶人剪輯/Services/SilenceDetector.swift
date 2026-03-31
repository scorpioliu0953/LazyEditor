import CoreMedia

struct SilenceDetector {
    nonisolated static func detectSilence(
        in waveform: [Float],
        config: SilenceDetectionConfig
    ) -> [CMTimeRange] {
        guard !waveform.isEmpty else { return [] }

        let threshold = config.linearThreshold
        let binsPerSecond = Double(Constants.waveformBinsPerSecond)
        let minBins = Int(config.minDuration * binsPerSecond)

        var silenceRanges: [CMTimeRange] = []
        var silenceStartBin: Int?

        for i in 0..<waveform.count {
            let isSilent = waveform[i] < threshold

            if isSilent {
                if silenceStartBin == nil {
                    silenceStartBin = i
                }
            } else {
                if let startBin = silenceStartBin {
                    let length = i - startBin
                    if length >= minBins {
                        let startTime = Double(startBin) / binsPerSecond
                        let endTime = Double(i) / binsPerSecond
                        silenceRanges.append(CMTimeRange(
                            start: .from(seconds: startTime),
                            duration: .from(seconds: endTime - startTime)
                        ))
                    }
                    silenceStartBin = nil
                }
            }
        }

        // 處理結尾靜音
        if let startBin = silenceStartBin {
            let length = waveform.count - startBin
            if length >= minBins {
                let startTime = Double(startBin) / binsPerSecond
                let endTime = Double(waveform.count) / binsPerSecond
                silenceRanges.append(CMTimeRange(
                    start: .from(seconds: startTime),
                    duration: .from(seconds: endTime - startTime)
                ))
            }
        }

        return silenceRanges
    }
}
