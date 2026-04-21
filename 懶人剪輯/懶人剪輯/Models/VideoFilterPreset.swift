import CoreImage
import AVFoundation

/// 匯出時字幕/字卡覆層快取（避免每幀重新繪製）
private final class ExportOverlayCache: @unchecked Sendable {
    private var cachedOverlay: CIImage?
    private var cachedKey: String = ""

    func getOrRender(key: String, render: () -> CIImage?) -> CIImage? {
        if key == cachedKey {
            return cachedOverlay
        }
        let overlay = render()
        cachedOverlay = overlay
        cachedKey = key
        return overlay
    }
}

enum VideoFilterPreset: String, CaseIterable, Identifiable {
    case none
    case naturalSoft
    case cinematicWarm
    case cinematicCool
    case japaneseFresh
    case vintageFilm
    case vivid
    case bwCinematic
    case goldenHour
    case tutorialClear
    case neonCity

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:           "無濾鏡"
        case .naturalSoft:    "自然柔和"
        case .cinematicWarm:  "電影暖調"
        case .cinematicCool:  "電影冷調"
        case .japaneseFresh:  "日系清新"
        case .vintageFilm:    "復古膠片"
        case .vivid:          "高對比鮮豔"
        case .bwCinematic:    "黑白質感"
        case .goldenHour:     "夕陽金色"
        case .tutorialClear:  "教學清晰"
        case .neonCity:       "霓虹都市"
        }
    }

    var description: String {
        switch self {
        case .none:           "不套用任何濾鏡效果"
        case .naturalSoft:    "微暖色溫 + 柔和對比，適合日常 Vlog"
        case .cinematicWarm:  "暖色調 + 高對比 + 暗角，營造電影感"
        case .cinematicCool:  "冷色調 + 高對比 + 暗角，科幻/懸疑風格"
        case .japaneseFresh:  "明亮曝光 + 低飽和，小清新文青風"
        case .vintageFilm:    "褪色暖調 + 低對比，復古膠片質感"
        case .vivid:          "高對比 + 高飽和度，色彩鮮豔有衝擊力"
        case .bwCinematic:    "黑白去飽和 + 高對比，質感黑白影像"
        case .goldenHour:     "金色暖調 + 微暗角，夕陽黃金時刻"
        case .tutorialClear:  "提亮 + 銳化，教學/講解專用清晰畫面"
        case .neonCity:       "青橙互補色 + 高飽和，都市夜景霓虹感"
        }
    }

    var iconColor: (r: Double, g: Double, b: Double) {
        switch self {
        case .none:           (0.5, 0.5, 0.5)
        case .naturalSoft:    (0.85, 0.78, 0.65)
        case .cinematicWarm:  (0.90, 0.60, 0.35)
        case .cinematicCool:  (0.40, 0.55, 0.80)
        case .japaneseFresh:  (0.80, 0.90, 0.85)
        case .vintageFilm:    (0.75, 0.65, 0.50)
        case .vivid:          (0.95, 0.40, 0.40)
        case .bwCinematic:    (0.45, 0.45, 0.45)
        case .goldenHour:     (0.95, 0.80, 0.40)
        case .tutorialClear:  (0.70, 0.85, 0.95)
        case .neonCity:       (0.30, 0.85, 0.85)
        }
    }

    // MARK: - CIFilter 套用

    /// 對 CIImage 套用濾鏡效果
    func apply(to image: CIImage) -> CIImage {
        switch self {
        case .none:
            return image

        case .naturalSoft:
            return image
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: 0.03,
                    kCIInputContrastKey: 1.05,
                    kCIInputSaturationKey: 1.05
                ])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 6900, y: 0)
                ])
                .applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: 0.3,
                    kCIInputRadiusKey: 2.0
                ])

        case .cinematicWarm:
            return image
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: -0.02,
                    kCIInputContrastKey: 1.15,
                    kCIInputSaturationKey: 0.95
                ])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 7500, y: 0)
                ])
                .applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: 0.8,
                    kCIInputRadiusKey: 1.5
                ])

        case .cinematicCool:
            return image
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: -0.02,
                    kCIInputContrastKey: 1.15,
                    kCIInputSaturationKey: 0.90
                ])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 5000, y: 0)
                ])
                .applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: 0.6,
                    kCIInputRadiusKey: 1.8
                ])

        case .japaneseFresh:
            return image
                .applyingFilter("CIExposureAdjust", parameters: [
                    kCIInputEVKey: 0.25
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: 0.04,
                    kCIInputContrastKey: 0.92,
                    kCIInputSaturationKey: 0.80
                ])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 6900, y: 5)
                ])

        case .vintageFilm:
            let adjusted = image
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: 0.02,
                    kCIInputContrastKey: 0.85,
                    kCIInputSaturationKey: 0.70
                ])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 7200, y: 10)
                ])
                .applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: 0.5,
                    kCIInputRadiusKey: 1.8
                ])
            // 提升暗部（褪色效果）
            return adjusted.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0.06, y: 0.05, z: 0.04, w: 0)
            ])

        case .vivid:
            return image
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: 0.0,
                    kCIInputContrastKey: 1.30,
                    kCIInputSaturationKey: 1.40
                ])
                .applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: 0.2,
                    kCIInputRadiusKey: 2.0
                ])

        case .bwCinematic:
            return image
                .applyingFilter("CIPhotoEffectMono")
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: 0.02,
                    kCIInputContrastKey: 1.25
                ])
                .applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: 0.4,
                    kCIInputRadiusKey: 1.8
                ])

        case .goldenHour:
            return image
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: 0.03,
                    kCIInputContrastKey: 1.10,
                    kCIInputSaturationKey: 1.10
                ])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 8000, y: 15)
                ])
                .applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: 0.4,
                    kCIInputRadiusKey: 1.8
                ])

        case .tutorialClear:
            return image
                .applyingFilter("CIExposureAdjust", parameters: [
                    kCIInputEVKey: 0.15
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: 0.04,
                    kCIInputContrastKey: 1.05,
                    kCIInputSaturationKey: 1.0
                ])
                .applyingFilter("CISharpenLuminance", parameters: [
                    kCIInputSharpnessKey: 0.5
                ])

        case .neonCity:
            // 青橙互補色調：壓暗中增加青色陰影 + 暖色高光
            return image
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: -0.02,
                    kCIInputContrastKey: 1.20,
                    kCIInputSaturationKey: 1.35
                ])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 5500, y: -15)
                ])
                .applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: 0.3,
                    kCIInputRadiusKey: 2.0
                ])
        }
    }

    // MARK: - 強度混合

    /// 套用濾鏡並以 intensity 混合（0 = 原始，1 = 完全濾鏡）
    func applyWithIntensity(to image: CIImage, intensity: Float) -> CIImage {
        guard intensity > 0 else { return image }
        let filtered = apply(to: image)
        guard intensity < 1 else { return filtered }

        // CIDissolveTransition: inputTime 0 = inputImage, 1 = inputTargetImage
        return filtered.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: image,
            "inputTime": NSNumber(value: 1.0 - intensity)
        ])
    }

    // MARK: - AVVideoComposition 建立

    /// 為 composition 建立帶濾鏡的 AVVideoComposition（用於預覽，不含字幕）
    func makeVideoComposition(
        for asset: AVAsset,
        intensity: Float = 1.0
    ) async -> AVMutableVideoComposition? {
        guard self != .none else { return nil }

        do {
            let renderSize = try await Self.resolveRenderSize(for: asset)

            let preset = self
            let capturedIntensity = intensity
            let videoComposition = try await AVMutableVideoComposition.videoComposition(
                with: asset,
                applyingCIFiltersWithHandler: { request in
                    let source = request.sourceImage.clampedToExtent()
                    let filtered = preset.applyWithIntensity(to: source, intensity: capturedIntensity)
                        .cropped(to: request.sourceImage.extent)
                    request.finish(with: filtered, context: nil)
                }
            )
            videoComposition.renderSize = renderSize

            return videoComposition
        } catch {
            debugLog("[Filter] 建立 videoComposition 失敗: \(error)")
            return nil
        }
    }

    /// 為匯出建立帶濾鏡 + 字幕燒錄 + 字卡的 AVVideoComposition
    static func makeExportVideoComposition(
        for asset: AVAsset,
        filter: VideoFilterPreset,
        intensity: Float,
        primaryTrack: SubtitleRenderer.TrackSnapshot?,
        secondaryTrack: SubtitleRenderer.TrackSnapshot?,
        textCardTrack: TextCardRenderer.TrackSnapshot? = nil
    ) async -> AVMutableVideoComposition? {
        let hasFilter = filter != .none
        let hasSubs = (primaryTrack?.isVisible == true && !(primaryTrack?.entries.isEmpty ?? true))
            || (secondaryTrack?.isVisible == true && !(secondaryTrack?.entries.isEmpty ?? true))
        let hasTextCards = !(textCardTrack?.entries.isEmpty ?? true)

        guard hasFilter || hasSubs || hasTextCards else { return nil }

        do {
            let renderSize = try await resolveRenderSize(for: asset)
            let overlayCache = ExportOverlayCache()
            let ciContext = CIContext(options: [.useSoftwareRenderer: false])

            let videoComposition = try await AVMutableVideoComposition.videoComposition(
                with: asset,
                applyingCIFiltersWithHandler: { request in
                    var output = request.sourceImage.clampedToExtent()

                    // 1) 套用濾鏡
                    if hasFilter {
                        output = filter.applyWithIntensity(to: output, intensity: intensity)
                    }

                    output = output.cropped(to: request.sourceImage.extent)

                    // 2) 燒錄字幕 + 字卡（使用快取避免每幀重新繪製）
                    if hasSubs || hasTextCards {
                        let time = request.compositionTime.seconds
                        let key = overlayKey(
                            time: time,
                            primaryTrack: hasSubs ? primaryTrack : nil,
                            secondaryTrack: hasSubs ? secondaryTrack : nil,
                            textCardTrack: hasTextCards ? textCardTrack : nil
                        )

                        if !key.isEmpty {
                            if let overlay = overlayCache.getOrRender(key: key, render: {
                                var result: CIImage? = nil

                                if hasSubs {
                                    result = SubtitleRenderer.renderOverlay(
                                        at: time,
                                        renderSize: renderSize,
                                        primaryTrack: primaryTrack,
                                        secondaryTrack: secondaryTrack
                                    )
                                }

                                if hasTextCards {
                                    if let tcOverlay = TextCardRenderer.renderOverlay(
                                        at: time,
                                        renderSize: renderSize,
                                        track: textCardTrack
                                    ) {
                                        result = result.map { tcOverlay.composited(over: $0) } ?? tcOverlay
                                    }
                                }

                                return result
                            }) {
                                output = overlay.composited(over: output)
                            }
                        }
                    }

                    request.finish(with: output, context: ciContext)
                }
            )
            videoComposition.renderSize = renderSize

            return videoComposition
        } catch {
            debugLog("[Export] 建立匯出 videoComposition 失敗: \(error)")
            return nil
        }
    }

    // MARK: - 輔助

    /// 計算覆層快取 key（相同 key 代表覆層不變，可重用）
    private static func overlayKey(
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
                        // 淡入淡出期間每幀不同，不快取
                        parts.append("t\(i)@\(Int(time * 30))")
                        continue
                    }
                }
                parts.append("t\(i)")
            }
        }

        return parts.joined(separator: "|")
    }

    private static func resolveRenderSize(for asset: AVAsset) async throws -> CGSize {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            return CGSize(width: 1920, height: 1080)
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)

        let isPortrait = transform.a == 0 && transform.d == 0
        if isPortrait {
            return CGSize(width: naturalSize.height, height: naturalSize.width)
        }
        return naturalSize
    }
}
