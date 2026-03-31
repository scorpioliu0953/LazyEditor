import AVFoundation

struct ProxyGenerator {
    /// 產生 540p 代理檔，用於剪輯預覽（匯出時仍使用原始檔）
    nonisolated static func generateProxy(
        for sourceAsset: AVURLAsset,
        progressHandler: @Sendable @escaping (Float) -> Void = { _ in }
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("proxy_\(UUID().uuidString).mp4")

        // 先嘗試 AVAssetExportSession（快速路徑）
        do {
            try await exportWithSession(sourceAsset: sourceAsset, outputURL: outputURL, progressHandler: progressHandler)
            return outputURL
        } catch {
            debugLog("[Proxy] ExportSession 失敗，改用 avconvert: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: outputURL)
        }

        // Fallback: 使用 macOS 內建 avconvert 命令列工具
        try await transcodeWithAVConvert(sourceURL: sourceAsset.url, outputURL: outputURL, progressHandler: progressHandler)
        return outputURL
    }

    // MARK: - 快速路徑：AVAssetExportSession

    private nonisolated static func exportWithSession(
        sourceAsset: AVURLAsset,
        outputURL: URL,
        progressHandler: @Sendable @escaping (Float) -> Void
    ) async throws {
        let preferredPresets = [
            AVAssetExportPreset960x540,
            AVAssetExportPreset640x480,
            AVAssetExportPresetLowQuality
        ]
        var chosenPreset = AVAssetExportPresetLowQuality
        for preset in preferredPresets {
            if AVAssetExportSession.exportPresets(compatibleWith: sourceAsset).contains(preset) {
                chosenPreset = preset
                break
            }
        }

        guard let session = AVAssetExportSession(
            asset: sourceAsset,
            presetName: chosenPreset
        ) else {
            throw ProxyError.cannotCreateSession
        }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        let pollTask = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                progressHandler(session.progress)
            }
        }

        do {
            try await session.export(to: outputURL, as: .mp4)
            pollTask.cancel()
            progressHandler(1.0)
        } catch {
            pollTask.cancel()
            throw error
        }
    }

    // MARK: - Fallback：avconvert 命令列工具

    private nonisolated static func transcodeWithAVConvert(
        sourceURL: URL,
        outputURL: URL,
        progressHandler: @Sendable @escaping (Float) -> Void
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/avconvert")
        process.arguments = [
            "--preset", "PresetHighestQuality",
            "--source", sourceURL.path,
            "--output", outputURL.path,
            "--verbose"
        ]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()

        // 等待完成
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            debugLog("[Proxy] avconvert 失敗 (exit \(process.terminationStatus)): \(output)")
            // 若 960x540 preset 不支援，改用較通用的 preset
            try? FileManager.default.removeItem(at: outputURL)
            try await transcodeWithAVConvertFallback(sourceURL: sourceURL, outputURL: outputURL, progressHandler: progressHandler)
            return
        }

        debugLog("[Proxy] avconvert 成功: \(sourceURL.lastPathComponent)")
        progressHandler(1.0)
    }

    private nonisolated static func transcodeWithAVConvertFallback(
        sourceURL: URL,
        outputURL: URL,
        progressHandler: @Sendable @escaping (Float) -> Void
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/avconvert")
        process.arguments = [
            "--preset", "PresetMediumQuality",
            "--source", sourceURL.path,
            "--output", outputURL.path
        ]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            debugLog("[Proxy] avconvert fallback 也失敗 (exit \(process.terminationStatus)): \(output)")
            throw ProxyError.exportFailed(
                NSError(domain: "ProxyGenerator", code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "avconvert 轉檔失敗"])
            )
        }

        debugLog("[Proxy] avconvert fallback 成功: \(sourceURL.lastPathComponent)")
        progressHandler(1.0)
    }

    enum ProxyError: Error, LocalizedError {
        case cannotCreateSession
        case exportFailed(Error)

        var errorDescription: String? {
            switch self {
            case .cannotCreateSession:
                "無法建立代理檔轉檔工作"
            case .exportFailed(let err):
                "代理檔產生失敗：\(err.localizedDescription)"
            }
        }
    }
}
