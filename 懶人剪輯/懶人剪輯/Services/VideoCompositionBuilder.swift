import AVFoundation
import MediaToolbox

func debugLog(_ msg: String) {
    let path = "/tmp/lazyeditor_debug.log"
    let line = "\(Date()): \(msg)\n"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

struct VideoCompositionBuilder {
    struct CompositionResult {
        let composition: AVMutableComposition
        let audioMix: AVMutableAudioMix?
    }

    nonisolated static func buildComposition(
        from segments: [ClipSegment],
        clips: [UUID: VideoClip],
        useProxy: Bool = false
    ) async throws -> AVMutableComposition {
        let result = try await buildCompositionWithMix(from: segments, clips: clips, useProxy: useProxy)
        return result.composition
    }

    nonisolated static func buildCompositionWithMix(
        from segments: [ClipSegment],
        clips: [UUID: VideoClip],
        useProxy: Bool = false,
        audioTap: MTAudioProcessingTap? = nil
    ) async throws -> CompositionResult {
        let composition = AVMutableComposition()

        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw CompositionError.cannotCreateTrack
        }

        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var insertionTime: CMTime = .zero
        var hasVolumeChanges = false
        var volumeRamps: [(time: CMTime, duration: CMTime, volume: Float)] = []

        for segment in segments {
            guard let clip = clips[segment.clipID] else { continue }

            let asset: AVURLAsset
            if useProxy {
                asset = clip.previewAsset
            } else if clip.isProxyReady, let proxyAsset = clip.proxyAsset {
                let exportPresets = AVAssetExportSession.exportPresets(compatibleWith: clip.asset)
                if exportPresets.contains(AVAssetExportPresetHighestQuality) {
                    asset = clip.asset
                } else {
                    asset = proxyAsset
                }
            } else {
                asset = clip.asset
            }

            // 使用高精度 timescale 避免 Double→CMTime 捨入誤差逐段累積
            // nativeTimescale 可能只有 600（精度 ~1.67ms），100 段會累積 ~167ms 漂移
            // 改用 600,000 精度 ~0.0017ms，即使 1000 段也 < 2ms
            let sourceVideoTracks = try await asset.loadTracks(withMediaType: .video)
            let precisionTimescale: CMTimeScale = 600_000

            let startTime = CMTimeMakeWithSeconds(segment.startTime, preferredTimescale: precisionTimescale)
            let endTime = CMTimeMakeWithSeconds(segment.endTime, preferredTimescale: precisionTimescale)
            let timeRange = CMTimeRangeFromTimeToTime(start: startTime, end: endTime)

            // 影片軌
            if let sourceVideoTrack = sourceVideoTracks.first {
                try videoTrack.insertTimeRange(
                    timeRange,
                    of: sourceVideoTrack,
                    at: insertionTime
                )
            }

            // 音軌
            if let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first,
               let audioTrack {
                try audioTrack.insertTimeRange(
                    timeRange,
                    of: sourceAudioTrack,
                    at: insertionTime
                )
            }

            // 音量
            if segment.volumeDB != 0 { hasVolumeChanges = true }
            volumeRamps.append((
                time: insertionTime,
                duration: timeRange.duration,
                volume: segment.linearVolume
            ))

            insertionTime = insertionTime + timeRange.duration
        }

        // 建立 audio mix（含微淡入淡出防止段落接合噠噠聲）
        var audioMix: AVMutableAudioMix? = nil
        if let audioTrack, (!volumeRamps.isEmpty || audioTap != nil) {
            let mix = AVMutableAudioMix()
            let params = AVMutableAudioMixInputParameters(track: audioTrack)
            params.audioTapProcessor = audioTap

            // 2ms 微淡化，消除分段接合處的噠噠聲
            let fadeDuration = CMTimeMakeWithSeconds(0.002, preferredTimescale: 48000)

            for ramp in volumeRamps {
                let segStart = ramp.time
                let segDuration = ramp.duration
                let segEnd = CMTimeAdd(segStart, segDuration)
                let vol = ramp.volume

                // 片段夠長才加微淡化（> 10ms）
                if CMTimeGetSeconds(segDuration) > 0.01 {
                    // 淡入：0 → vol
                    params.setVolumeRamp(
                        fromStartVolume: 0,
                        toEndVolume: vol,
                        timeRange: CMTimeRange(start: segStart, duration: fadeDuration)
                    )
                    // 淡出：vol → 0
                    let fadeOutStart = CMTimeSubtract(segEnd, fadeDuration)
                    params.setVolumeRamp(
                        fromStartVolume: vol,
                        toEndVolume: 0,
                        timeRange: CMTimeRange(start: fadeOutStart, duration: fadeDuration)
                    )
                } else {
                    params.setVolume(vol, at: segStart)
                }
            }

            mix.inputParameters = [params]
            audioMix = mix
        }

        // 診斷：記錄影片/音軌實際長度，確認同步
        let finalVideoRange = videoTrack.timeRange
        let finalAudioRange = audioTrack?.timeRange ?? .zero
        debugLog("[Composition] 影片軌: \(finalVideoRange.duration.seconds)s, 音軌: \(finalAudioRange.duration.seconds)s, 差異: \((finalVideoRange.duration.seconds - finalAudioRange.duration.seconds) * 1000)ms, 段落數: \(segments.count)")

        return CompositionResult(composition: composition, audioMix: audioMix)
    }

    enum CompositionError: Error, LocalizedError {
        case cannotCreateTrack

        var errorDescription: String? {
            switch self {
            case .cannotCreateTrack:
                "無法建立合成軌道"
            }
        }
    }
}
