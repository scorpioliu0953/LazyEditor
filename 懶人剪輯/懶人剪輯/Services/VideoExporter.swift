import AVFoundation
import CoreImage

struct VideoExporter {

    // MARK: - 音訊匯出

    /// 匯出音訊（M4A 使用 AVAssetExportSession；WAV/MP3 經由暫存 M4A 轉換）
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

        if ext == "m4a" {
            try await exportAudioViaSession(
                asset: composition,
                audioMix: audioMix,
                to: outputURL,
                progressHandler: progressHandler
            )
        } else if ext == "wav" {
            let tempM4A = fm.temporaryDirectory.appendingPathComponent("temp_\(UUID().uuidString).m4a")
            defer { try? fm.removeItem(at: tempM4A) }

            try await exportAudioViaSession(
                asset: composition,
                audioMix: audioMix,
                to: tempM4A
            ) { progress in
                progressHandler(progress * 0.5)
            }

            try await convertToWAV(from: tempM4A, to: outputURL) { progress in
                progressHandler(0.5 + progress * 0.5)
            }
        } else if ext == "mp3" {
            let tempM4A = fm.temporaryDirectory.appendingPathComponent("temp_\(UUID().uuidString).m4a")
            defer { try? fm.removeItem(at: tempM4A) }

            try await exportAudioViaSession(
                asset: composition,
                audioMix: audioMix,
                to: tempM4A
            ) { progress in
                progressHandler(progress * 0.6)
            }
            progressHandler(0.6)

            let args = ["-hide_banner", "-i", tempM4A.path,
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
        } else {
            try await exportAudioViaSession(
                asset: composition,
                audioMix: audioMix,
                to: outputURL,
                progressHandler: progressHandler
            )
        }
    }

    /// 用 AVAssetExportSession 匯出音訊
    private nonisolated static func exportAudioViaSession(
        asset: AVAsset,
        audioMix: AVMutableAudioMix?,
        to outputURL: URL,
        progressHandler: @Sendable @escaping (Float) -> Void
    ) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ExportError.cannotCreateSession
        }
        session.outputURL = outputURL
        session.outputFileType = .m4a
        if let audioMix { session.audioMix = audioMix }

        let progressTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                progressHandler(session.progress)
            }
        }

        await session.export()
        progressTimer.cancel()

        guard session.status == .completed else {
            throw ExportError.exportFailed(session.error)
        }
        progressHandler(1.0)
        debugLog("[AudioExport] AVAssetExportSession 完成: \(outputURL.lastPathComponent)")
    }

    /// M4A → WAV 轉換
    private nonisolated static func convertToWAV(
        from inputURL: URL,
        to outputURL: URL,
        progressHandler: @Sendable @escaping (Float) -> Void
    ) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: inputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw ExportError.exportFailed(nil)
        }

        let reader = try AVAssetReader(asset: asset)
        let aro = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        reader.add(aro)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)

        let fds = try await audioTrack.load(.formatDescriptions)
        var sampleRate: Double = 48000
        var channels: UInt32 = 2
        if let fd = fds.first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd as! CMAudioFormatDescription) {
            sampleRate = asbd.pointee.mSampleRate
            channels = asbd.pointee.mChannelsPerFrame
        }

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        writer.add(writerInput)

        guard reader.startReading() else { throw ExportError.exportFailed(reader.error) }
        guard writer.startWriting() else { throw ExportError.exportFailed(writer.error) }
        writer.startSession(atSourceTime: .zero)

        let duration = try await asset.load(.duration).seconds

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var lastProgressTime = CACurrentMediaTime()
                while let buffer = aro.copyNextSampleBuffer() {
                    while !writerInput.isReadyForMoreMediaData {
                        Thread.sleep(forTimeInterval: 0.005)
                    }
                    writerInput.append(buffer)
                    let now = CACurrentMediaTime()
                    if now - lastProgressTime > 0.1 {
                        lastProgressTime = now
                        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
                        progressHandler(Float(min(pts.seconds / duration, 1.0)))
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
    }

    // MARK: - 帶濾鏡影片匯出

    /// 帶濾鏡匯出（手動逐幀 CIFilter 渲染，繞過 AVAssetReaderVideoCompositionOutput 死鎖）：
    /// 1. AVAssetExportSession 預渲染乾淨音訊 → 暫存 M4A
    /// 2. AVAssetReaderTrackOutput 讀取原始幀 → 手動 CIFilter → AVAssetWriter 暫存 MP4
    /// 3. ffmpeg -c copy 取影片軌 + 乾淨音訊 → 最終 MP4
    nonisolated static func exportWithFilter(
        composition: AVMutableComposition,
        filter: VideoFilterPreset = .none,
        filterIntensity: Float = 1.0,
        primaryTrack: SubtitleRenderer.TrackSnapshot? = nil,
        secondaryTrack: SubtitleRenderer.TrackSnapshot? = nil,
        textCardTrack: TextCardRenderer.TrackSnapshot? = nil,
        audioMix: AVMutableAudioMix?,
        to outputURL: URL,
        progressHandler: @Sendable @escaping (Float) -> Void
    ) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }

        let tempVideoURL = fm.temporaryDirectory.appendingPathComponent("export_video_\(UUID().uuidString).mp4")
        let tempAudioURL = fm.temporaryDirectory.appendingPathComponent("export_audio_\(UUID().uuidString).m4a")

        defer {
            try? fm.removeItem(at: tempVideoURL)
            try? fm.removeItem(at: tempAudioURL)
        }

        // ── Step 1: 預渲染乾淨音訊 ──
        let hasAudio = !(try await composition.loadTracks(withMediaType: .audio)).isEmpty

        if hasAudio {
            guard let audioSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetAppleM4A
            ) else {
                throw ExportError.cannotCreateSession
            }
            audioSession.outputURL = tempAudioURL
            audioSession.outputFileType = .m4a
            if let audioMix { audioSession.audioMix = audioMix }

            await audioSession.export()

            guard audioSession.status == .completed else {
                throw ExportError.exportFailed(audioSession.error)
            }
            debugLog("[Export] Step1: 音訊預渲染完成")
        }

        // ── Step 2: 純影片逐幀渲染（不含音訊，避免 interleaving 死鎖）──
        let videoTracks = try await composition.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw ExportError.exportFailed(nil)
        }

        let reader = try AVAssetReader(asset: composition)

        // 只讀影片幀（不加音訊 output，徹底避免 interleaving 死鎖）
        let vro = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        )
        reader.add(vro)

        // 計算渲染尺寸與旋轉
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let isPortrait = preferredTransform.a == 0 && preferredTransform.d == 0
        let renderSize = isPortrait
            ? CGSize(width: naturalSize.height, height: naturalSize.width)
            : naturalSize

        let writer = try AVAssetWriter(outputURL: tempVideoURL, fileType: .mp4)
        let bitrate = Int(renderSize.width * renderSize.height) * 10

        let vwi = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        vwi.expectsMediaDataInRealTime = false

        // 判斷是否需要逐幀處理
        let hasFilter = filter != .none
        let hasSubs = (primaryTrack?.isVisible == true && !(primaryTrack?.entries.isEmpty ?? true))
            || (secondaryTrack?.isVisible == true && !(secondaryTrack?.entries.isEmpty ?? true))
        let hasTextCards = !(textCardTrack?.entries.isEmpty ?? true)
        let needsProcessing = hasFilter || hasSubs || hasTextCards || isPortrait

        var adaptor: AVAssetWriterInputPixelBufferAdaptor? = nil
        if needsProcessing {
            adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: vwi,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                    kCVPixelBufferWidthKey as String: Int(renderSize.width),
                    kCVPixelBufferHeightKey as String: Int(renderSize.height)
                ]
            )
        }
        writer.add(vwi)

        guard reader.startReading() else { throw ExportError.exportFailed(reader.error) }
        guard writer.startWriting() else { throw ExportError.exportFailed(writer.error) }
        writer.startSession(atSourceTime: .zero)

        let ciContext = needsProcessing
            ? CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
            : nil

        // 覆層快取
        var cachedOverlayKey = ""
        var cachedOverlay: CIImage? = nil

        let totalSeconds = try await composition.load(.duration).seconds
        let writeQueue = DispatchQueue(label: "com.lazyeditor.videoWrite", qos: .userInitiated)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var frameCount = 0
            var lastProgressTime = CACurrentMediaTime()
            var didResume = false

            // 純影片寫入（單一軌道，單一 queue，無 interleaving 風險）
            vwi.requestMediaDataWhenReady(on: writeQueue) {
                while vwi.isReadyForMoreMediaData {
                    guard let sampleBuffer = vro.copyNextSampleBuffer() else {
                        vwi.markAsFinished()
                        guard !didResume else { return }
                        didResume = true
                        if reader.status == .failed {
                            writer.cancelWriting()
                            cont.resume(throwing: ExportError.exportFailed(reader.error))
                            return
                        }
                        writer.finishWriting {
                            if writer.status == .failed {
                                cont.resume(throwing: ExportError.exportFailed(writer.error))
                            } else {
                                debugLog("[Export] Step2: 寫入完成, 共 \(frameCount) 幀")
                                cont.resume()
                            }
                        }
                        return
                    }

                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                    if needsProcessing,
                       let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                       let adaptor,
                       let ciContext {
                        autoreleasepool {
                            var image = CIImage(cvPixelBuffer: pixelBuffer)

                            // 套用旋轉（直向影片）
                            if isPortrait {
                                image = image.transformed(by: preferredTransform)
                                let origin = image.extent.origin
                                if origin.x != 0 || origin.y != 0 {
                                    image = image.transformed(by: CGAffineTransform(
                                        translationX: -origin.x, y: -origin.y
                                    ))
                                }
                            }

                            let targetExtent = CGRect(origin: .zero, size: renderSize)

                            // 套用濾鏡
                            if hasFilter {
                                image = image.clampedToExtent()
                                image = filter.applyWithIntensity(to: image, intensity: filterIntensity)
                                image = image.cropped(to: targetExtent)
                            }

                            // 套用字幕 + 字卡覆層
                            if hasSubs || hasTextCards {
                                let time = pts.seconds
                                let key = exportOverlayKey(
                                    time: time,
                                    primaryTrack: hasSubs ? primaryTrack : nil,
                                    secondaryTrack: hasSubs ? secondaryTrack : nil,
                                    textCardTrack: hasTextCards ? textCardTrack : nil
                                )
                                if !key.isEmpty {
                                    let overlay: CIImage?
                                    if key == cachedOverlayKey {
                                        overlay = cachedOverlay
                                    } else {
                                        var result: CIImage? = nil
                                        if hasSubs {
                                            result = SubtitleRenderer.renderOverlay(
                                                at: time, renderSize: renderSize,
                                                primaryTrack: primaryTrack,
                                                secondaryTrack: secondaryTrack
                                            )
                                        }
                                        if hasTextCards {
                                            if let tcOverlay = TextCardRenderer.renderOverlay(
                                                at: time, renderSize: renderSize,
                                                track: textCardTrack
                                            ) {
                                                result = result.map { tcOverlay.composited(over: $0) } ?? tcOverlay
                                            }
                                        }
                                        cachedOverlay = result
                                        cachedOverlayKey = key
                                        overlay = result
                                    }
                                    if let overlay {
                                        image = overlay.composited(over: image)
                                    }
                                }
                            }

                            // 渲染到輸出 pixel buffer
                            guard let pool = adaptor.pixelBufferPool else { return }
                            var outputPB: CVPixelBuffer?
                            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputPB)
                            guard let outputPB else { return }

                            ciContext.render(image, to: outputPB)
                            adaptor.append(outputPB, withPresentationTime: pts)
                        }
                    } else {
                        vwi.append(sampleBuffer)
                    }

                    frameCount += 1
                    let now = CACurrentMediaTime()
                    if now - lastProgressTime > 0.2 {
                        lastProgressTime = now
                        progressHandler(Float(min(pts.seconds / totalSeconds, 1.0)) * 0.9)
                    }
                }
            }
        }

        debugLog("[Export] Step2: 影片渲染完成")
        progressHandler(0.9)

        // ── Step 3: 原生 AVFoundation 合併影片 + 音訊 ──
        if hasAudio {
            let videoSize = (try? fm.attributesOfItem(atPath: tempVideoURL.path)[.size] as? Int64) ?? 0
            let audioSize = (try? fm.attributesOfItem(atPath: tempAudioURL.path)[.size] as? Int64) ?? 0
            debugLog("[Export] Step3: 暫存影片 \(videoSize) bytes, 暫存音訊 \(audioSize) bytes")

            let videoAsset = AVURLAsset(url: tempVideoURL)
            let audioAsset = AVURLAsset(url: tempAudioURL)

            let muxComp = AVMutableComposition()

            // 加入影片軌
            if let srcVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
               let dstVideoTrack = muxComp.addMutableTrack(
                   withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let videoDuration = try await videoAsset.load(.duration)
                try dstVideoTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: videoDuration),
                    of: srcVideoTrack, at: .zero
                )
            }

            // 加入音訊軌
            if let srcAudioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
               let dstAudioTrack = muxComp.addMutableTrack(
                   withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let videoDuration = try await videoAsset.load(.duration)
                let audioDuration = try await audioAsset.load(.duration)
                let safeDuration = CMTimeMinimum(videoDuration, audioDuration)
                try dstAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: safeDuration),
                    of: srcAudioTrack, at: .zero
                )
            }

            // Passthrough 匯出（單檔 → 單檔，不會損壞音訊）
            guard let muxSession = AVAssetExportSession(
                asset: muxComp,
                presetName: AVAssetExportPresetPassthrough
            ) else {
                throw ExportError.cannotCreateSession
            }
            muxSession.outputURL = outputURL
            muxSession.outputFileType = .mp4

            await muxSession.export()

            guard muxSession.status == .completed else {
                debugLog("[Export] Step3: Passthrough mux 失敗: \(muxSession.error?.localizedDescription ?? "未知")")
                throw ExportError.exportFailed(muxSession.error)
            }
        } else {
            try fm.moveItem(at: tempVideoURL, to: outputURL)
        }

        progressHandler(1.0)
        debugLog("[Export] 匯出完成: \(outputURL.lastPathComponent)")
    }

    // MARK: - 覆層快取 key

    private static func exportOverlayKey(
        time: Double,
        primaryTrack: SubtitleRenderer.TrackSnapshot?,
        secondaryTrack: SubtitleRenderer.TrackSnapshot?,
        textCardTrack: TextCardRenderer.TrackSnapshot?
    ) -> String {
        var parts: [String] = []

        if let pt = primaryTrack, pt.isVisible {
            if let idx = pt.entries.firstIndex(where: { time >= $0.startTime && time < $0.endTime }) {
                parts.append("p\(idx)")
            }
        }

        if let st = secondaryTrack, st.isVisible {
            if let idx = st.entries.firstIndex(where: { time >= $0.startTime && time < $0.endTime }) {
                parts.append("s\(idx)")
            }
        }

        if let tc = textCardTrack {
            let fadeDur = 0.3
            for (i, card) in tc.entries.enumerated() {
                guard time >= card.startTime && time < card.endTime else { continue }
                if card.fadeInOut {
                    let elapsed = time - card.startTime
                    let remaining = card.endTime - time
                    if elapsed < fadeDur || remaining < fadeDur {
                        parts.append("t\(i)@\(Int(time * 30))")
                        continue
                    }
                }
                parts.append("t\(i)")
            }
        }

        return parts.joined(separator: "|")
    }

    // MARK: - Errors

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
