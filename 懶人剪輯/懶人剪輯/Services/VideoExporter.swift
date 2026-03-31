import AVFoundation

struct VideoExporter {
    /// 使用 AVAssetReader + AVAssetWriter 匯出 composition 為 MP4
    /// 影片軌：passthrough（不重編碼，保留原始品質）
    /// 音軌：解碼為 PCM → 重編碼 AAC（正確處理 priming，避免同步漂移）
    nonisolated static func export(
        composition: AVMutableComposition,
        to outputURL: URL,
        audioMix: AVMutableAudioMix? = nil,
        progressHandler: @Sendable @escaping (Float) -> Void
    ) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }

        // 載入軌道
        let videoTracks = try await composition.loadTracks(withMediaType: .video)
        let audioTracks = try await composition.loadTracks(withMediaType: .audio)

        guard let sourceVideoTrack = videoTracks.first else {
            throw ExportError.exportFailed(nil)
        }

        // 取得影片軌的實際長度作為統一基準
        let videoTimeRange = try await sourceVideoTrack.load(.timeRange)
        let totalDuration = videoTimeRange.duration

        // ── Reader ──
        let reader = try AVAssetReader(asset: composition)
        reader.timeRange = CMTimeRange(start: .zero, duration: totalDuration)

        // 影片：passthrough（outputSettings = nil）
        let videoFormatDescs = try await sourceVideoTrack.load(.formatDescriptions)
        let videoReaderOutput = AVAssetReaderTrackOutput(
            track: sourceVideoTrack,
            outputSettings: nil
        )
        videoReaderOutput.alwaysCopiesSampleData = false
        reader.add(videoReaderOutput)

        // 音訊：解碼為 PCM Float32
        var audioReaderOutput: AVAssetReaderOutput?
        var sourceSampleRate: Double = 48000
        var sourceChannels: UInt32 = 2

        if let sourceAudioTrack = audioTracks.first {
            let audioFormatDescs = try await sourceAudioTrack.load(.formatDescriptions)
            if let desc = audioFormatDescs.first,
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc as! CMAudioFormatDescription) {
                sourceSampleRate = asbd.pointee.mSampleRate
                sourceChannels = asbd.pointee.mChannelsPerFrame
            }

            let pcmSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsNonInterleaved: false
            ]

            if let audioMix {
                let mixOutput = AVAssetReaderAudioMixOutput(
                    audioTracks: audioTracks,
                    audioSettings: pcmSettings
                )
                mixOutput.audioMix = audioMix
                reader.add(mixOutput)
                audioReaderOutput = mixOutput
            } else {
                let trackOutput = AVAssetReaderTrackOutput(
                    track: sourceAudioTrack,
                    outputSettings: pcmSettings
                )
                trackOutput.alwaysCopiesSampleData = false
                reader.add(trackOutput)
                audioReaderOutput = trackOutput
            }
        }

        // ── Writer ──
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // 影片 Writer Input：passthrough
        let videoFormatHint = videoFormatDescs.first as! CMFormatDescription?
        let videoWriterInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: nil,
            sourceFormatHint: videoFormatHint
        )
        videoWriterInput.expectsMediaDataInRealTime = false

        // 保留影片方向
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        videoWriterInput.transform = preferredTransform

        writer.add(videoWriterInput)

        // 音訊 Writer Input：AAC 編碼
        var audioWriterInput: AVAssetWriterInput?
        if audioReaderOutput != nil {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: sourceSampleRate,
                AVNumberOfChannelsKey: sourceChannels,
                AVEncoderBitRateKey: 256_000
            ]
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: audioSettings
            )
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioWriterInput = input
        }

        // ── 開始讀寫 ──
        guard reader.startReading() else {
            throw ExportError.exportFailed(reader.error)
        }
        guard writer.startWriting() else {
            throw ExportError.exportFailed(writer.error)
        }
        writer.startSession(atSourceTime: .zero)

        let totalSeconds = totalDuration.seconds

        // 使用純 GCD 迴圈，避免 requestMediaDataWhenReady 與 Swift concurrency 的死鎖
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let group = DispatchGroup()

            // 影片寫入
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                var lastProgressTime = CACurrentMediaTime()
                while let buffer = videoReaderOutput.copyNextSampleBuffer() {
                    while !videoWriterInput.isReadyForMoreMediaData {
                        Thread.sleep(forTimeInterval: 0.005)
                    }
                    videoWriterInput.append(buffer)
                    let now = CACurrentMediaTime()
                    if now - lastProgressTime > 0.1 {
                        lastProgressTime = now
                        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
                        progressHandler(Float(min(pts.seconds / totalSeconds, 1.0)) * 0.9)
                    }
                }
                videoWriterInput.markAsFinished()
                group.leave()
            }

            // 音訊寫入
            if let audioWriterInput, let audioReaderOutput {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    while let buffer = audioReaderOutput.copyNextSampleBuffer() {
                        while !audioWriterInput.isReadyForMoreMediaData {
                            Thread.sleep(forTimeInterval: 0.005)
                        }
                        audioWriterInput.append(buffer)
                    }
                    audioWriterInput.markAsFinished()
                    group.leave()
                }
            }

            group.notify(queue: .global()) {
                progressHandler(0.95)
                writer.finishWriting {
                    if writer.status == .failed {
                        cont.resume(throwing: ExportError.exportFailed(writer.error))
                    } else {
                        cont.resume()
                    }
                }
            }
        }

        progressHandler(1.0)
        debugLog("[Export] Reader+Writer 匯出完成: \(outputURL.lastPathComponent) duration=\(totalSeconds)s")
    }

    /// 匯出音訊：使用 AVAssetReader + AVAssetWriter 直接從 composition 讀取 PCM 並寫入
    nonisolated static func exportAudio(
        composition: AVMutableComposition,
        audioMix: AVMutableAudioMix?,
        to outputURL: URL,
        progressHandler: @Sendable @escaping (Float) -> Void
    ) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }

        let ext = outputURL.pathExtension.lowercased()

        if ext == "mp3" {
            // MP3: 先輸出 WAV，再用 ffmpeg 轉 MP3
            let tempWAV = fm.temporaryDirectory
                .appendingPathComponent("temp_audio_\(UUID().uuidString).wav")
            defer { try? fm.removeItem(at: tempWAV) }

            try await writeAudioDirect(
                composition: composition,
                audioMix: audioMix,
                to: tempWAV,
                fileType: .wav,
                encoderSettings: nil
            ) { progress in
                progressHandler(progress * 0.6)
            }

            progressHandler(0.6)

            let args = ["-hide_banner", "-i", tempWAV.path,
                        "-acodec", "libmp3lame", "-b:a", "192k", "-write_xing", "1",
                        "-y", outputURL.path]
            debugLog("[AudioExport] ffmpeg \(args.joined(separator: " "))")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/ffmpeg")
            process.arguments = args
            let pipe = Pipe()
            process.standardError = pipe
            process.standardOutput = pipe
            try process.run()

            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in cont.resume() }
            }

            if process.terminationStatus != 0 {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMsg = String(data: errorData, encoding: .utf8) ?? ""
                debugLog("[AudioExport] ffmpeg MP3 轉換失敗: \(errorMsg)")
                throw ExportError.exportFailed(
                    NSError(domain: "VideoExporter", code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "MP3 轉換失敗"])
                )
            }

            progressHandler(1.0)
        } else if ext == "wav" {
            try await writeAudioDirect(
                composition: composition,
                audioMix: audioMix,
                to: outputURL,
                fileType: .wav,
                encoderSettings: nil
            ) { progress in
                progressHandler(progress)
            }
        } else {
            // M4A: 直接用 AVAssetWriter 編碼 AAC
            try await writeAudioDirect(
                composition: composition,
                audioMix: audioMix,
                to: outputURL,
                fileType: .m4a,
                encoderSettings: [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVEncoderBitRateKey: 256_000
                ]
            ) { progress in
                progressHandler(progress)
            }
        }
    }

    /// AVAssetReader → AVAssetWriter 直寫音頻（純 GCD，不用 requestMediaDataWhenReady）
    private nonisolated static func writeAudioDirect(
        composition: AVMutableComposition,
        audioMix: AVMutableAudioMix?,
        to outputURL: URL,
        fileType: AVFileType,
        encoderSettings: [String: Any]?,
        progressHandler: @Sendable @escaping (Float) -> Void
    ) async throws {
        let audioTracks = try await composition.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw ExportError.exportFailed(nil)
        }

        // 以影片軌長度為準
        let videoTracks = try await composition.loadTracks(withMediaType: .video)
        let targetDuration: CMTime
        if let vt = videoTracks.first {
            targetDuration = try await vt.load(.timeRange).duration
        } else {
            targetDuration = try await audioTrack.load(.timeRange).duration
        }

        // Reader: 解碼為 PCM（使用 AudioMixOutput 以支援音量調整）
        let reader = try AVAssetReader(asset: composition)
        reader.timeRange = CMTimeRange(start: .zero, duration: targetDuration)

        let pcmSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false
        ]

        let readerOutput: AVAssetReaderOutput
        if let audioMix {
            let mixOutput = AVAssetReaderAudioMixOutput(
                audioTracks: audioTracks,
                audioSettings: pcmSettings
            )
            mixOutput.audioMix = audioMix
            readerOutput = mixOutput
        } else {
            readerOutput = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: pcmSettings
            )
        }
        reader.add(readerOutput)

        // Writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)

        // 讀取來源音軌的取樣率與聲道數
        let formatDescs = try await audioTrack.load(.formatDescriptions)
        var sampleRate: Double = 48000
        var channels: UInt32 = 2
        if let desc = formatDescs.first {
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc as! CMAudioFormatDescription)
            if let asbd {
                sampleRate = asbd.pointee.mSampleRate
                channels = asbd.pointee.mChannelsPerFrame
            }
        }

        let writerSettings: [String: Any]
        if var encoderSettings {
            encoderSettings[AVSampleRateKey] = sampleRate
            encoderSettings[AVNumberOfChannelsKey] = channels
            writerSettings = encoderSettings
        } else {
            // WAV: PCM 16-bit
            writerSettings = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        }

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
        writer.add(writerInput)

        guard reader.startReading() else {
            throw ExportError.exportFailed(reader.error)
        }
        guard writer.startWriting() else {
            throw ExportError.exportFailed(writer.error)
        }
        writer.startSession(atSourceTime: .zero)

        let totalSeconds = targetDuration.seconds

        // 純 GCD 迴圈 + finishWriting callback，避免與 Swift concurrency 死鎖
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var lastProgressTime = CACurrentMediaTime()
                while let buffer = readerOutput.copyNextSampleBuffer() {
                    while !writerInput.isReadyForMoreMediaData {
                        Thread.sleep(forTimeInterval: 0.005)
                    }
                    writerInput.append(buffer)
                    let now = CACurrentMediaTime()
                    if now - lastProgressTime > 0.1 {
                        lastProgressTime = now
                        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
                        progressHandler(Float(min(pts.seconds / totalSeconds, 1.0)))
                    }
                }
                writerInput.markAsFinished()
                writer.finishWriting {
                    if writer.status == .failed {
                        cont.resume(throwing: ExportError.exportFailed(writer.error))
                    } else {
                        cont.resume()
                    }
                }
            }
        }

        progressHandler(1.0)
        debugLog("[AudioExport] 音訊直寫完成: \(outputURL.lastPathComponent) duration=\(targetDuration.seconds)s")
    }

    /// 執行 ffmpeg 命令
    private nonisolated static func runFFmpeg(args: [String]) async throws {
        debugLog("[ffmpeg] \(args.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/ffmpeg")
        process.arguments = args
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        try process.run()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }

        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? ""
            debugLog("[ffmpeg] 失敗: \(errorMsg)")
            throw ExportError.exportFailed(
                NSError(domain: "VideoExporter", code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "ffmpeg 失敗"])
            )
        }
    }

    /// 帶濾鏡匯出（使用 AVAssetExportSession，需重編碼影片）
    nonisolated static func exportWithFilter(
        composition: AVMutableComposition,
        videoComposition: AVVideoComposition,
        audioMix: AVMutableAudioMix?,
        to outputURL: URL,
        progressHandler: @Sendable @escaping (Float) -> Void
    ) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.cannotCreateSession
        }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        if let audioMix { session.audioMix = audioMix }

        // 進度輪詢
        let progressTask = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                progressHandler(session.progress)
            }
        }

        await session.export()
        progressTask.cancel()

        switch session.status {
        case .completed:
            progressHandler(1.0)
            debugLog("[Export] 濾鏡匯出完成: \(outputURL.lastPathComponent)")
        case .failed:
            throw ExportError.exportFailed(session.error)
        case .cancelled:
            throw ExportError.cancelled
        default:
            throw ExportError.exportFailed(session.error)
        }
    }

    enum ExportError: Error, LocalizedError {
        case cannotCreateSession
        case exportFailed(Error?)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .cannotCreateSession:
                "無法建立匯出工作階段"
            case .exportFailed(let err):
                "匯出失敗：\(err?.localizedDescription ?? "未知錯誤")"
            case .cancelled:
                "匯出已取消"
            }
        }
    }
}
