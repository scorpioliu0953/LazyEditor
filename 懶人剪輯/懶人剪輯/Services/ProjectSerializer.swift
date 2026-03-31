import Foundation
import AVFoundation

struct ProjectSerializer {

    enum SerializeError: Error, LocalizedError {
        case bookmarkFailed(URL)
        case decodeFailed(String)
        case encodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .bookmarkFailed(let url):
                "無法建立書籤: \(url.lastPathComponent)"
            case .decodeFailed(let msg):
                "專案讀取失敗: \(msg)"
            case .encodeFailed(let msg):
                "專案儲存失敗: \(msg)"
            }
        }
    }

    // MARK: - 儲存

    static func save(vm: ProjectViewModel, to url: URL) throws {
        let doc = try buildDocument(from: vm)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(doc)
        try data.write(to: url, options: .atomic)
        debugLog("[Project] 儲存完成: \(url.lastPathComponent)")
    }

    private static func buildDocument(from vm: ProjectViewModel) throws -> ProjectDocument {
        var doc = ProjectDocument()

        // Clips
        for clip in vm.clips.values {
            let bookmark: Data
            do {
                bookmark = try clip.url.bookmarkData(options: .withSecurityScope)
            } catch {
                debugLog("[Project] 書籤建立失敗: \(clip.url.lastPathComponent) - \(error)")
                continue
            }
            doc.clips.append(ClipDocument(
                id: clip.id.uuidString,
                bookmark: bookmark,
                duration: clip.duration
            ))
        }

        // Segments
        for seg in vm.timeline.segments {
            doc.segments.append(SegmentDocument(
                id: seg.id.uuidString,
                clipID: seg.clipID.uuidString,
                startTime: seg.startTime,
                endTime: seg.endTime,
                volumeDB: seg.volumeDB
            ))
        }

        // Subtitles
        doc.primarySubtitle = encodeSubtitleTrack(vm.primarySubtitleTrack)
        if !vm.secondarySubtitleTrack.entries.isEmpty {
            doc.secondarySubtitle = encodeSubtitleTrack(vm.secondarySubtitleTrack)
        }

        // Text cards
        if !vm.textCardTrack.entries.isEmpty {
            doc.textCards = vm.textCardTrack.entries.map {
                TextCardEntryDocument(
                    id: $0.id.uuidString,
                    startTime: $0.startTime,
                    endTime: $0.endTime,
                    text: $0.text,
                    style: $0.style.rawValue,
                    positionX: Double($0.positionX),
                    positionY: Double($0.positionY),
                    scale: Double($0.scale),
                    widthRatio: Double($0.widthRatio)
                )
            }
        }

        // Audio settings
        let as_ = vm.audioSettings
        doc.audioSettings = AudioSettingsDocument(
            volumeDB: as_.volumeDB,
            eqEnabled: as_.eqEnabled,
            eqPreset: as_.eqPreset.rawValue,
            bands: as_.bands,
            noiseReductionEnabled: as_.noiseReductionEnabled,
            noiseReductionStrength: as_.noiseReductionStrength,
            levelingEnabled: as_.levelingEnabled,
            levelingAmount: as_.levelingAmount
        )

        // Silence config
        doc.silenceConfig = SilenceConfigDocument(
            thresholdDB: vm.silenceConfig.thresholdDB,
            minDuration: vm.silenceConfig.minDuration,
            paddingDuration: vm.silenceConfig.paddingDuration
        )

        // Filter
        doc.filterPreset = vm.selectedFilter.rawValue
        doc.filterIntensity = vm.filterIntensity

        // Timeline state
        doc.playheadPosition = vm.timeline.playheadPosition
        doc.zoomScale = Double(vm.timelineVM.zoomScale)

        return doc
    }

    private static func encodeSubtitleTrack(_ track: SubtitleTrack) -> SubtitleTrackDocument {
        SubtitleTrackDocument(
            entries: track.entries.map {
                SubtitleEntryDocument(
                    id: $0.id.uuidString,
                    startTime: $0.startTime,
                    endTime: $0.endTime,
                    text: $0.text
                )
            },
            settings: SubtitleSettingsDocument(
                fontName: track.settings.fontName,
                fontSizeRatio: Double(track.settings.fontSizeRatio),
                verticalPositionRatio: Double(track.settings.verticalPositionRatio),
                strokeWidth: Double(track.settings.strokeWidth)
            ),
            language: track.language.rawValue,
            isVisible: track.isVisible
        )
    }

    // MARK: - 載入

    static func load(from url: URL, into vm: ProjectViewModel) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let doc = try decoder.decode(ProjectDocument.self, from: data)

        // 清除現有狀態
        vm.clips.removeAll()
        vm.timeline.segments.removeAll()
        vm.timeline.clearSelection()

        // 解析 bookmarks → 建立 clips
        var clipMap: [String: UUID] = [:] // docID → actual UUID

        for clipDoc in doc.clips {
            guard let clipUUID = UUID(uuidString: clipDoc.id) else { continue }

            var isStale = false
            do {
                let resolvedURL = try URL(
                    resolvingBookmarkData: clipDoc.bookmark,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                let accessed = resolvedURL.startAccessingSecurityScopedResource()
                let clip = VideoClip(id: clipUUID, url: resolvedURL)
                clip.duration = clipDoc.duration
                vm.clips[clip.id] = clip
                clipMap[clipDoc.id] = clip.id

                if isStale {
                    debugLog("[Project] 書籤已過期（仍可讀取）: \(resolvedURL.lastPathComponent)")
                }

                // 背景載入波形 + proxy
                Task {
                    defer {
                        if accessed { resolvedURL.stopAccessingSecurityScopedResource() }
                    }
                    do {
                        let waveform = try await AudioWaveformExtractor.extractWaveform(from: clip.asset)
                        clip.waveformData = waveform
                    } catch {
                        debugLog("[Project] 波形提取失敗: \(error)")
                    }

                    clip.isGeneratingProxy = true
                    vm.proxyGeneratingCount += 1
                    do {
                        let proxyURL = try await ProxyGenerator.generateProxy(for: clip.asset)
                        clip.proxyURL = proxyURL
                        clip.proxyAsset = AVURLAsset(url: proxyURL)
                        clip.isProxyReady = true
                        clip.isGeneratingProxy = false
                        vm.proxyGeneratingCount -= 1
                        vm.rebuildComposition()
                    } catch {
                        clip.isGeneratingProxy = false
                        vm.proxyGeneratingCount -= 1
                        debugLog("[Project] Proxy 失敗: \(error)")
                    }
                }
            } catch {
                debugLog("[Project] 書籤解析失敗: \(clipDoc.id) - \(error)")
                continue
            }
        }

        // 還原 segments
        for segDoc in doc.segments {
            guard let clipUUID = UUID(uuidString: segDoc.clipID),
                  vm.clips[clipUUID] != nil else {
                debugLog("[Project] 跳過 segment（找不到 clip）: \(segDoc.clipID)")
                continue
            }

            let segment = ClipSegment(
                clipID: clipUUID,
                startTime: segDoc.startTime,
                endTime: segDoc.endTime,
                volumeDB: segDoc.volumeDB
            )
            vm.timeline.segments.append(segment)
        }

        // 還原字幕
        if let primary = doc.primarySubtitle {
            decodeSubtitleTrack(primary, into: vm.primarySubtitleTrack)
        }
        if let secondary = doc.secondarySubtitle {
            decodeSubtitleTrack(secondary, into: vm.secondarySubtitleTrack)
        }

        // 還原字卡
        vm.textCardTrack.entries.removeAll()
        if let textCards = doc.textCards {
            vm.textCardTrack.entries = textCards.compactMap { cardDoc in
                guard let id = UUID(uuidString: cardDoc.id),
                      let style = TextCardStyle(rawValue: cardDoc.style) else { return nil }
                return TextCardEntry(
                    id: id,
                    startTime: cardDoc.startTime,
                    endTime: cardDoc.endTime,
                    text: cardDoc.text,
                    style: style,
                    positionX: CGFloat(cardDoc.positionX),
                    positionY: CGFloat(cardDoc.positionY),
                    scale: CGFloat(cardDoc.scale),
                    widthRatio: CGFloat(cardDoc.widthRatio)
                )
            }
        }

        // 還原音訊設定
        let as_ = doc.audioSettings
        vm.audioSettings.volumeDB = as_.volumeDB
        vm.audioSettings.eqEnabled = as_.eqEnabled
        if let preset = EQPreset(rawValue: as_.eqPreset) {
            vm.audioSettings.eqPreset = preset
        }
        vm.audioSettings.bands = as_.bands
        vm.audioSettings.noiseReductionEnabled = as_.noiseReductionEnabled
        vm.audioSettings.noiseReductionStrength = as_.noiseReductionStrength
        vm.audioSettings.levelingEnabled = as_.levelingEnabled
        vm.audioSettings.levelingAmount = as_.levelingAmount

        // 還原靜音偵測設定
        vm.silenceConfig.thresholdDB = doc.silenceConfig.thresholdDB
        vm.silenceConfig.minDuration = doc.silenceConfig.minDuration
        vm.silenceConfig.paddingDuration = doc.silenceConfig.paddingDuration

        // 還原濾鏡
        if let filter = VideoFilterPreset(rawValue: doc.filterPreset) {
            vm.selectedFilter = filter
        }
        vm.filterIntensity = doc.filterIntensity

        // 還原播放頭與縮放
        vm.timeline.playheadPosition = doc.playheadPosition
        vm.timelineVM.zoomScale = CGFloat(doc.zoomScale)

        // 重建 composition
        vm.rebuildComposition()

        debugLog("[Project] 載入完成: \(url.lastPathComponent), \(vm.clips.count) clips, \(vm.timeline.segments.count) segments")
    }

    private static func decodeSubtitleTrack(_ doc: SubtitleTrackDocument, into track: SubtitleTrack) {
        track.entries = doc.entries.compactMap { entryDoc in
            guard let id = UUID(uuidString: entryDoc.id) else { return nil }
            return SubtitleEntry(
                id: id,
                startTime: entryDoc.startTime,
                endTime: entryDoc.endTime,
                text: entryDoc.text
            )
        }
        track.settings.fontName = doc.settings.fontName
        track.settings.fontSizeRatio = CGFloat(doc.settings.fontSizeRatio)
        track.settings.verticalPositionRatio = CGFloat(doc.settings.verticalPositionRatio)
        track.settings.strokeWidth = CGFloat(doc.settings.strokeWidth)
        if let lang = SubtitleLanguage(rawValue: doc.language) {
            track.language = lang
        }
        track.isVisible = doc.isVisible
    }
}
