import AVFoundation

struct AudioProcessor {
    /// 離線處理音頻：讀取 composition 音軌 → AVAudioEngine 處理 → 輸出 .m4a 暫存檔
    nonisolated static func processAudio(
        from composition: AVMutableComposition,
        settings: AudioSettingsSnapshot,
        progressHandler: @Sendable @escaping (Float) -> Void
    ) async throws -> URL {
        let audioTracks = try await composition.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw ProcessingError.noAudioTrack
        }

        // 讀取來源音軌的取樣率與聲道數，避免重取樣造成長度偏差
        let formatDescs = try await audioTrack.load(.formatDescriptions)
        var sampleRate: Double = 48000
        var channels: AVAudioChannelCount = 2
        if let desc = formatDescs.first {
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc as! CMAudioFormatDescription) {
                sampleRate = asbd.pointee.mSampleRate
                channels = AVAudioChannelCount(asbd.pointee.mChannelsPerFrame)
            }
        }
        let processingFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channels
        )!

        // 讀取所有音頻樣本（interleaved Float32）
        let allSamples = try readAllAudioSamples(
            from: composition,
            track: audioTrack,
            sampleRate: sampleRate,
            channels: channels
        )

        let totalFrames = allSamples.count / Int(channels)
        guard totalFrames > 0 else { throw ProcessingError.noAudioData }

        // 轉為 non-interleaved AVAudioPCMBuffer
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: processingFormat,
            frameCapacity: AVAudioFrameCount(totalFrames)
        ) else {
            throw ProcessingError.bufferCreationFailed
        }
        inputBuffer.frameLength = AVAudioFrameCount(totalFrames)

        for ch in 0..<Int(channels) {
            guard let channelPtr = inputBuffer.floatChannelData?[ch] else { continue }
            for frame in 0..<totalFrames {
                channelPtr[frame] = allSamples[frame * Int(channels) + ch]
            }
        }

        // 建立 AVAudioEngine 處理鏈（EQ + 去雜音）
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)

        var currentNode: AVAudioNode = playerNode

        // EQ
        let eq = AVAudioUnitEQ(numberOfBands: 5)
        engine.attach(eq)
        engine.connect(currentNode, to: eq, format: processingFormat)
        currentNode = eq

        // 去雜音：高通濾波器
        if settings.noiseReductionEnabled {
            let noiseFilter = AVAudioUnitEQ(numberOfBands: 2)
            let hpBand = noiseFilter.bands[0]
            hpBand.filterType = .highPass
            hpBand.frequency = 60 + 140 * settings.noiseReductionStrength
            hpBand.bypass = false

            let notchBand = noiseFilter.bands[1]
            notchBand.filterType = .parametric
            notchBand.frequency = 120
            notchBand.bandwidth = 0.5
            notchBand.gain = -6 * settings.noiseReductionStrength
            notchBand.bypass = false

            engine.attach(noiseFilter)
            engine.connect(currentNode, to: noiseFilter, format: processingFormat)
            currentNode = noiseFilter
        }

        // 連接到輸出（不在 engine 層套用音量和壓縮，改用後處理）
        engine.connect(currentNode, to: engine.mainMixerNode, format: processingFormat)
        engine.mainMixerNode.volume = 1.0

        // 離線渲染模式
        let maxFrames: AVAudioFrameCount = 4096
        try engine.enableManualRenderingMode(.offline, format: processingFormat, maximumFrameCount: maxFrames)

        // EQ 必須在 attach + connect 之後設定參數，避免被引擎重置
        configureEQ(eq, settings: settings, format: processingFormat)

        try engine.start()

        playerNode.play()
        playerNode.scheduleBuffer(inputBuffer, completionHandler: nil)

        // 輸出檔案
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("processed_\(UUID().uuidString).m4a")

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 192000
        ]
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        // 渲染迴圈 + 逐 chunk 後處理
        var renderedFrames: AVAudioFramePosition = 0
        let totalToRender = AVAudioFramePosition(totalFrames)
        var stallCount = 0
        var envelope: Float = 0 // 壓縮器包絡狀態

        while renderedFrames < totalToRender {
            let remaining = AVAudioFrameCount(totalToRender - renderedFrames)
            let framesToRender = min(maxFrames, remaining)

            guard let renderBuffer = AVAudioPCMBuffer(
                pcmFormat: engine.manualRenderingFormat,
                frameCapacity: framesToRender
            ) else { break }

            let status = try engine.renderOffline(framesToRender, to: renderBuffer)

            switch status {
            case .success:
                // 後處理：音量平衡（動態壓縮）
                if settings.levelingEnabled {
                    envelope = applyLeveling(
                        to: renderBuffer,
                        envelope: envelope,
                        sampleRate: sampleRate,
                        amount: settings.levelingAmount
                    )
                }

                // 後處理：整體音量增益
                if settings.volumeDB != 0 {
                    applyVolume(to: renderBuffer, gain: settings.linearVolume)
                }

                try outputFile.write(from: renderBuffer)
                renderedFrames += AVAudioFramePosition(renderBuffer.frameLength)
                stallCount = 0
                progressHandler(Float(renderedFrames) / Float(totalToRender))

            case .insufficientDataFromInputNode:
                stallCount += 1
                if stallCount > 10 { break }

            case .cannotDoInCurrentContext:
                try? await Task.sleep(for: .milliseconds(1))

            case .error:
                throw ProcessingError.renderFailed

            @unknown default:
                break
            }

            if stallCount > 10 { break }
        }

        engine.stop()
        return outputURL
    }

    // MARK: - 後處理：動態壓縮

    /// 對 buffer 套用軟膝壓縮，回傳更新後的包絡值（供下一 chunk 銜接）
    private nonisolated static func applyLeveling(
        to buffer: AVAudioPCMBuffer,
        envelope: Float,
        sampleRate: Double,
        amount: Float
    ) -> Float {
        let frameCount = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard let channelData = buffer.floatChannelData, frameCount > 0 else { return envelope }

        let threshold: Float = powf(10.0, (-30 + 15 * amount) / 20.0)
        let ratio: Float = 2.0 + 6.0 * amount          // 2:1 ~ 8:1
        let makeupGain: Float = powf(10.0, (3 * amount) / 20.0)
        let attackCoeff: Float = expf(-1.0 / (Float(sampleRate) * 0.01))
        let releaseCoeff: Float = expf(-1.0 / (Float(sampleRate) * 0.1))

        var env = envelope

        for frame in 0..<frameCount {
            // 計算 RMS 電平
            var sumSquares: Float = 0
            for ch in 0..<channels {
                let sample = channelData[ch][frame]
                sumSquares += sample * sample
            }
            let level = sqrtf(sumSquares / Float(channels))

            // 包絡追蹤
            if level > env {
                env = attackCoeff * env + (1 - attackCoeff) * level
            } else {
                env = releaseCoeff * env + (1 - releaseCoeff) * level
            }

            // 計算增益衰減
            var gain: Float = 1.0
            if env > threshold {
                let dbOver = 20 * log10f(env / threshold)
                let dbReduction = dbOver * (1.0 - 1.0 / ratio)
                gain = powf(10.0, -dbReduction / 20.0)
            }
            gain *= makeupGain

            for ch in 0..<channels {
                channelData[ch][frame] *= gain
            }
        }

        return env
    }

    // MARK: - 後處理：音量增益

    private nonisolated static func applyVolume(to buffer: AVAudioPCMBuffer, gain: Float) {
        let frameCount = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard let channelData = buffer.floatChannelData else { return }

        for ch in 0..<channels {
            for frame in 0..<frameCount {
                channelData[ch][frame] *= gain
            }
        }
    }

    // MARK: - 讀取音頻樣本

    private nonisolated static func readAllAudioSamples(
        from asset: AVAsset,
        track: AVAssetTrack,
        sampleRate: Double,
        channels: AVAudioChannelCount
    ) throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else {
            throw ProcessingError.readerFailed(reader.error)
        }

        var allSamples: [Float] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var length = 0
            var dataPtr: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(
                blockBuffer, atOffset: 0,
                lengthAtOffsetOut: nil, totalLengthOut: &length,
                dataPointerOut: &dataPtr
            )
            guard let ptr = dataPtr else { continue }
            let floatCount = length / MemoryLayout<Float>.size
            let floatPtr = UnsafeRawPointer(ptr).bindMemory(to: Float.self, capacity: floatCount)
            allSamples.append(contentsOf: UnsafeBufferPointer(start: floatPtr, count: floatCount))
        }

        return allSamples
    }

    // MARK: - EQ 設定

    private nonisolated static func configureEQ(
        _ eq: AVAudioUnitEQ,
        settings: AudioSettingsSnapshot,
        format: AVAudioFormat
    ) {
        let frequencies = AudioSettings.bandFrequencies
        for (i, band) in eq.bands.enumerated() {
            band.frequency = frequencies[i]
            band.gain = settings.eqEnabled ? settings.bands[i] : 0
            band.bypass = !settings.eqEnabled

            switch i {
            case 0:
                // 80Hz：低頻架式，影響所有低頻
                band.filterType = .lowShelf
            case 4:
                // 12kHz：高頻架式，影響所有高頻
                band.filterType = .highShelf
            default:
                // 中間頻段：參數型（1 八度，效果更集中明顯）
                band.filterType = .parametric
                band.bandwidth = 1.0
            }
        }
    }

    enum ProcessingError: Error, LocalizedError {
        case noAudioTrack
        case noAudioData
        case bufferCreationFailed
        case converterFailed
        case renderFailed
        case readerFailed(Error?)

        var errorDescription: String? {
            switch self {
            case .noAudioTrack: "影片沒有音軌"
            case .noAudioData: "音頻資料為空"
            case .bufferCreationFailed: "無法建立音頻緩衝區"
            case .converterFailed: "音頻格式轉換失敗"
            case .renderFailed: "音頻渲染失敗"
            case .readerFailed(let e): "讀取音頻失敗：\(e?.localizedDescription ?? "")"
            }
        }
    }
}
