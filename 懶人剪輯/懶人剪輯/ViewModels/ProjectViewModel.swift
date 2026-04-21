import AVFoundation
import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

@Observable
final class ProjectViewModel {
    var clips: [UUID: VideoClip] = [:]
    var timeline = TimelineState()
    var toolMode: ToolMode = .selection
    var silenceConfig = SilenceDetectionConfig()
    var audioSettings = AudioSettings()

    // MARK: - 濾鏡
    var selectedFilter: VideoFilterPreset = .none
    var filterIntensity: Float = 1.0 // 0.0 ~ 1.0

    // MARK: - 字卡
    var textCardTrack = TextCardTrack()
    var selectedTextCardID: UUID?
    var isEditingTextCard: Bool = false

    // MARK: - 字幕
    var primarySubtitleTrack: SubtitleTrack = {
        let track = SubtitleTrack()
        track.language = .chinese
        track.settings.fontName = "PingFang TC"
        track.settings.fontSizeRatio = 0.055
        track.settings.verticalPositionRatio = 0.88
        return track
    }()
    var secondarySubtitleTrack: SubtitleTrack = {
        let track = SubtitleTrack()
        track.language = .english
        track.settings.fontName = "Helvetica Neue"
        track.settings.fontSizeRatio = 0.035
        track.settings.verticalPositionRatio = 0.95
        return track
    }()

    /// 代理檔產生中的數量
    var proxyGeneratingCount: Int = 0

    // MARK: - 專案儲存/載入
    var currentProjectURL: URL?
    var isDirty: Bool = false
    var autoSaveConfig = AutoSaveConfig()
    private var autoSaveTimer: Timer?

    let playback = PlaybackViewModel()
    let timelineVM = TimelineViewModel()
    let exportVM = ExportViewModel()

    private var compositionTask: Task<Void, Never>?
    private var filterUpdateTask: Task<Void, Never>?

    // MARK: - 素材列表

    /// 按 segments 出現順序去重排列的 clips
    var orderedClips: [VideoClip] {
        var seen = Set<UUID>()
        var result: [VideoClip] = []
        for segment in timeline.segments {
            if !seen.contains(segment.clipID), let clip = clips[segment.clipID] {
                seen.insert(segment.clipID)
                result.append(clip)
            }
        }
        return result
    }

    /// 拖曳排序 segments
    func reorderSegments(fromOffsets: IndexSet, toOffset: Int) {
        timeline.pushUndo()
        timeline.segments.move(fromOffsets: fromOffsets, toOffset: toOffset)
        rebuildComposition()
    }

    /// 計算某個 segment 在時間軸上的起始位置（秒）
    func timelineStartPosition(for segmentID: UUID) -> Double {
        var position: Double = 0
        for segment in timeline.segments {
            if segment.id == segmentID { return position }
            position += segment.duration
        }
        return position
    }

    /// 跳到指定 segment 的開頭
    func seekToSegment(_ segmentID: UUID) {
        let position = timelineStartPosition(for: segmentID)
        timeline.playheadPosition = position
        playback.seek(to: position)
    }

    /// 刪除指定的單一 segment
    func deleteSegment(_ segmentID: UUID) {
        timeline.pushUndo()
        timeline.segments.removeAll { $0.id == segmentID }
        timeline.selectedSegmentIDs.remove(segmentID)
        rebuildComposition()
    }

    /// 設定片段音量（dB）
    func setSegmentVolume(_ segmentID: UUID, db: Float) {
        timeline.pushUndo()
        if let idx = timeline.segments.firstIndex(where: { $0.id == segmentID }) {
            timeline.segments[idx].volumeDB = db
        }
        rebuildComposition()
    }

    // MARK: - 復原

    func undo() {
        timeline.undo()
        rebuildComposition()
    }

    // MARK: - 匯入

    func showImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]
        panel.title = "匯入影片"
        panel.prompt = "匯入"

        guard panel.runModal() == .OK else { return }
        importFiles(urls: panel.urls)
    }

    func importFiles(urls: [URL]) {
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard Constants.supportedVideoTypes.contains(ext) else { continue }

            let accessGranted = url.startAccessingSecurityScopedResource()

            let clip = VideoClip(url: url)
            clips[clip.id] = clip

            Task {
                defer {
                    if accessGranted { url.stopAccessingSecurityScopedResource() }
                }

                // 先載入時長，再加入 segment（避免零時長 segment 導致空 composition）
                let duration: Double
                do {
                    let cmDuration = try await clip.asset.load(.duration)
                    duration = cmDuration.seconds
                    guard duration.isFinite && duration > 0 else {
                        debugLog("[Import] 無效時長: \(url.lastPathComponent) duration=\(cmDuration.seconds)")
                        clips.removeValue(forKey: clip.id)
                        return
                    }
                } catch {
                    debugLog("[Import] 無法載入時長: \(url.lastPathComponent) error=\(error.localizedDescription)")
                    clips.removeValue(forKey: clip.id)
                    return
                }

                clip.duration = duration
                let segment = ClipSegment(
                    clipID: clip.id,
                    startTime: 0,
                    endTime: duration
                )
                timeline.segments.append(segment)

                do {
                    let waveform = try await AudioWaveformExtractor.extractWaveform(from: clip.asset)
                    clip.waveformData = waveform
                } catch {
                    print("波形提取失敗：\(error.localizedDescription)")
                }

                rebuildComposition()

                // 在同一個 Task 內 await 代理檔產生，確保 security scope 存活
                clip.isGeneratingProxy = true
                proxyGeneratingCount += 1
                do {
                    let proxyURL = try await ProxyGenerator.generateProxy(for: clip.asset)
                    clip.proxyURL = proxyURL
                    clip.proxyAsset = AVURLAsset(url: proxyURL)
                    clip.isProxyReady = true
                    clip.isGeneratingProxy = false
                    proxyGeneratingCount -= 1
                    debugLog("[Proxy] 成功: \(url.lastPathComponent) → \(proxyURL.lastPathComponent)")
                    rebuildComposition()
                } catch {
                    clip.isGeneratingProxy = false
                    proxyGeneratingCount -= 1
                    debugLog("[Proxy] 失敗: \(url.lastPathComponent) error=\(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - 選取

    /// 處理片段選取，支援 Shift/Command 修飾鍵
    func selectSegment(id: UUID, shift: Bool, command: Bool) {
        if shift {
            timeline.extendSelection(to: id)
        } else if command {
            timeline.toggleSelection(id)
        } else {
            timeline.selectOnly(id)
        }
    }

    // MARK: - 時間軸操作

    func bladeAt(segmentID: UUID, localTime: Double) {
        timeline.pushUndo()
        // playheadPosition 已在裁切點，rebuildComposition 會自動恢復
        timeline.segments = timeline.segments.splitting(segmentID: segmentID, at: localTime)
        rebuildComposition()
    }

    func deleteSelectedSegments() {
        guard !timeline.selectedSegmentIDs.isEmpty else { return }
        timeline.pushUndo()
        let toRemove = timeline.selectedSegmentIDs

        // 找出被刪除片段中最早的時間軸起始位置
        var deleteStartPosition: Double = .infinity
        for seg in timeline.segments {
            if toRemove.contains(seg.id) {
                let pos = timelineStartPosition(for: seg.id)
                if pos < deleteStartPosition {
                    deleteStartPosition = pos
                }
            }
        }

        timeline.segments.removeAll { toRemove.contains($0.id) }
        timeline.clearSelection()

        // 播放頭移到刪除位置（即下一個片段的開頭）
        let seekPosition = min(deleteStartPosition, timeline.totalDuration)
        timeline.playheadPosition = seekPosition

        rebuildComposition()
    }

    func removeAllSilence() {
        guard !clips.isEmpty else { return }

        timeline.pushUndo()

        var newSegments: [ClipSegment] = []

        for segment in timeline.segments {
            guard let clip = clips[segment.clipID],
                  let waveform = clip.waveformData else {
                newSegments.append(segment)
                continue
            }

            let bps = Constants.waveformBinsPerSecond
            let startBin = Int(segment.startTime * Double(bps))
            let endBin = min(Int(segment.endTime * Double(bps)), waveform.count)

            guard startBin < endBin else {
                newSegments.append(segment)
                continue
            }

            let segmentWaveform = Array(waveform[startBin..<endBin])

            let silenceRanges = SilenceDetector.detectSilence(
                in: segmentWaveform,
                config: silenceConfig
            )

            // 將靜音範圍轉為絕對時間
            let absoluteRanges = silenceRanges.map { range -> CMTimeRange in
                let absStart = segment.startTime + range.startSeconds
                return CMTimeRange(
                    start: .from(seconds: absStart),
                    duration: range.duration
                )
            }

            let kept = segment.excludingRanges(absoluteRanges, padding: silenceConfig.paddingDuration)
            newSegments.append(contentsOf: kept)
        }

        timeline.segments = newSegments
        timeline.clearSelection()
        rebuildComposition()
    }

    // MARK: - 點擊時間軸定位播放

    func seekTimeline(to timelineX: CGFloat) {
        let time = timelineVM.xToTime(timelineX)
        let clampedTime = max(0, min(time, timeline.totalDuration))
        timeline.playheadPosition = clampedTime
        playback.seek(to: clampedTime)
    }

    // MARK: - 音頻

    /// 即時套用音量到播放器預覽
    func applyVolumeToPlayback() {
        playback.player.volume = audioSettings.linearVolume
    }

    /// 即時更新 EQ 預覽參數（透過 MTAudioProcessingTap 即時生效）
    func updateEQPreview() {
        playback.eqTapContext.updateSettings(
            enabled: audioSettings.eqEnabled,
            bands: audioSettings.bands
        )
    }

    // MARK: - 濾鏡即時預覽（不重建 composition）

    /// 僅更新 videoComposition（濾鏡強度/種類），不重建整個 composition
    func updateFilterPreview() {
        filterUpdateTask?.cancel()
        filterUpdateTask = Task {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }

            guard let currentItem = playback.player.currentItem else { return }
            let asset = currentItem.asset

            let videoComp = await selectedFilter.makeVideoComposition(
                for: asset,
                intensity: filterIntensity
            )
            currentItem.videoComposition = videoComp
        }
    }

    // MARK: - 匯出

    func exportVideo() {
        guard let outputURL = exportVM.showSavePanel() else { return }

        exportVM.isExporting = true
        exportVM.exportProgress = 0
        exportVM.exportError = nil

        let settingsSnapshot = audioSettings.snapshot()
        let needsAudioProcessing = audioSettings.hasAnyChange
        let filterPreset = selectedFilter
        let filterIntensityVal = filterIntensity
        let primarySnap = SubtitleRenderer.snapshot(from: primarySubtitleTrack)
        let secondarySnap = SubtitleRenderer.snapshot(from: secondarySubtitleTrack)
        let textCardSnap = TextCardRenderer.snapshot(from: textCardTrack)
        let soundEffectCards = textCardTrack.entries.filter { $0.soundEffect != .none }
            .map { (startTime: $0.startTime, effect: $0.soundEffect) }

        Task {
            var processedAudioURL: URL? = nil
            defer {
                if let url = processedAudioURL {
                    try? FileManager.default.removeItem(at: url)
                }
            }

            do {
                let result = try await VideoCompositionBuilder.buildCompositionWithMix(
                    from: timeline.segments,
                    clips: clips
                )
                let composition = result.composition

                // 混入字卡音效
                if !soundEffectCards.isEmpty {
                    let precisionTimescale: CMTimeScale = 600_000
                    for sfx in soundEffectCards {
                        guard let sfxURL = SoundEffectGenerator.shared.urlForEffect(sfx.effect) else { continue }
                        let sfxAsset = AVURLAsset(url: sfxURL)
                        guard let sfxAudioTrack = try? await sfxAsset.loadTracks(withMediaType: .audio).first,
                              let sfxTrack = composition.addMutableTrack(
                                  withMediaType: .audio,
                                  preferredTrackID: kCMPersistentTrackID_Invalid
                              ) else { continue }
                        let sfxDuration = try await sfxAsset.load(.duration)
                        let insertTime = CMTimeMakeWithSeconds(sfx.startTime, preferredTimescale: precisionTimescale)
                        try? sfxTrack.insertTimeRange(
                            CMTimeRange(start: .zero, duration: sfxDuration),
                            of: sfxAudioTrack,
                            at: insertTime
                        )
                    }
                }

                let exportVM = self.exportVM

                if needsAudioProcessing {
                    let audioURL = try await AudioProcessor.processAudio(
                        from: composition,
                        settings: settingsSnapshot
                    ) { progress in
                        Task { @MainActor in
                            exportVM.exportProgress = progress * 0.3
                        }
                    }
                    processedAudioURL = audioURL

                    let existingAudioTracks = try await composition.loadTracks(withMediaType: .audio)
                    for track in existingAudioTracks {
                        composition.removeTrack(track)
                    }

                    let processedAsset = AVURLAsset(url: audioURL)
                    if let processedTrack = try await processedAsset.loadTracks(withMediaType: .audio).first,
                       let newAudioTrack = composition.addMutableTrack(
                           withMediaType: .audio,
                           preferredTrackID: kCMPersistentTrackID_Invalid
                       ) {
                        let videoTracks = try await composition.loadTracks(withMediaType: .video)
                        let targetDuration: CMTime
                        if let vt = videoTracks.first {
                            targetDuration = try await vt.load(.timeRange).duration
                        } else {
                            targetDuration = try await processedAsset.load(.duration)
                        }
                        let audioDuration = try await processedAsset.load(.duration)
                        let safeDuration = CMTimeMinimum(targetDuration, audioDuration)
                        try newAudioTrack.insertTimeRange(
                            CMTimeRange(start: .zero, duration: safeDuration),
                            of: processedTrack,
                            at: .zero
                        )
                    }

                    try await VideoExporter.exportWithFilter(
                        composition: composition,
                        filter: filterPreset,
                        filterIntensity: filterIntensityVal,
                        primaryTrack: primarySnap,
                        secondaryTrack: secondarySnap,
                        textCardTrack: textCardSnap,
                        audioMix: nil,
                        to: outputURL
                    ) { progress in
                        Task { @MainActor in
                            exportVM.exportProgress = 0.3 + progress * 0.7
                        }
                    }
                } else {
                    try await VideoExporter.exportWithFilter(
                        composition: composition,
                        filter: filterPreset,
                        filterIntensity: filterIntensityVal,
                        primaryTrack: primarySnap,
                        secondaryTrack: secondarySnap,
                        textCardTrack: textCardSnap,
                        audioMix: result.audioMix,
                        to: outputURL
                    ) { progress in
                        Task { @MainActor in
                            exportVM.exportProgress = progress
                        }
                    }
                }

                exportVM.exportProgress = 1.0
                exportVM.isExporting = false
                debugLog("[Export] 影片匯出完成: \(outputURL.lastPathComponent)")
            } catch {
                exportVM.isExporting = false
                exportVM.exportError = error.localizedDescription
                debugLog("[Export] 影片匯出失敗: \(error)")
            }
        }
    }

    /// 純音訊匯出（使用 AVAssetExportSession 最簡路徑）
    func exportAudioOnly() {
        guard let outputURL = exportVM.showSavePanelForAudio() else { return }

        exportVM.isExporting = true
        exportVM.exportProgress = 0
        exportVM.exportError = nil

        let soundEffectCards = textCardTrack.entries.filter { $0.soundEffect != .none }
            .map { (startTime: $0.startTime, effect: $0.soundEffect) }

        Task {
            do {
                let result = try await VideoCompositionBuilder.buildCompositionWithMix(
                    from: timeline.segments,
                    clips: clips
                )
                let composition = result.composition

                // 混入字卡音效
                if !soundEffectCards.isEmpty {
                    let precisionTimescale: CMTimeScale = 600_000
                    for sfx in soundEffectCards {
                        guard let sfxURL = SoundEffectGenerator.shared.urlForEffect(sfx.effect) else { continue }
                        let sfxAsset = AVURLAsset(url: sfxURL)
                        guard let sfxAudioTrack = try? await sfxAsset.loadTracks(withMediaType: .audio).first,
                              let sfxTrack = composition.addMutableTrack(
                                  withMediaType: .audio,
                                  preferredTrackID: kCMPersistentTrackID_Invalid
                              ) else { continue }
                        let sfxDuration = try await sfxAsset.load(.duration)
                        let insertTime = CMTimeMakeWithSeconds(sfx.startTime, preferredTimescale: precisionTimescale)
                        try? sfxTrack.insertTimeRange(
                            CMTimeRange(start: .zero, duration: sfxDuration),
                            of: sfxAudioTrack,
                            at: insertTime
                        )
                    }
                }

                // 直接用 AVAssetExportSession（Apple 原生最可靠路徑）
                guard let session = AVAssetExportSession(
                    asset: composition,
                    presetName: AVAssetExportPresetAppleM4A
                ) else {
                    throw VideoExporter.ExportError.cannotCreateSession
                }

                let fm = FileManager.default
                if fm.fileExists(atPath: outputURL.path) {
                    try fm.removeItem(at: outputURL)
                }

                session.outputURL = outputURL
                session.outputFileType = .m4a
                session.audioMix = result.audioMix

                let exportVM = self.exportVM

                // 輪詢進度
                let progressTimer = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(200))
                        let p = session.progress
                        await MainActor.run { exportVM.exportProgress = p }
                    }
                }

                await session.export()
                progressTimer.cancel()

                if session.status == .completed {
                    exportVM.exportProgress = 1.0
                    exportVM.isExporting = false
                    debugLog("[Export] 純音訊匯出完成: \(outputURL.lastPathComponent)")
                } else {
                    throw VideoExporter.ExportError.exportFailed(session.error)
                }
            } catch {
                exportVM.isExporting = false
                exportVM.exportError = error.localizedDescription
                debugLog("[Export] 純音訊匯出失敗: \(error)")
            }
        }
    }

    // MARK: - 字幕操作

    func updateSubtitleEntry(trackIndex: Int, entryID: UUID, text: String, startTime: Double, endTime: Double) {
        let track = trackIndex == 0 ? primarySubtitleTrack : secondarySubtitleTrack
        if let idx = track.entries.firstIndex(where: { $0.id == entryID }) {
            track.entries[idx].text = text
            track.entries[idx].startTime = startTime
            track.entries[idx].endTime = endTime
        }
    }

    // MARK: - 字卡操作

    func updateTextCardPosition(id: UUID, x: CGFloat, y: CGFloat) {
        if let idx = textCardTrack.entries.firstIndex(where: { $0.id == id }) {
            textCardTrack.entries[idx].positionX = x
            textCardTrack.entries[idx].positionY = y
            markDirty()
        }
    }

    func updateTextCardScale(id: UUID, scale: CGFloat) {
        if let idx = textCardTrack.entries.firstIndex(where: { $0.id == id }) {
            textCardTrack.entries[idx].scale = scale
            markDirty()
        }
    }

    func updateTextCardText(id: UUID, text: String) {
        if let idx = textCardTrack.entries.firstIndex(where: { $0.id == id }) {
            textCardTrack.entries[idx].text = text
            markDirty()
        }
    }

    func updateTextCardSize(id: UUID, widthRatio: CGFloat, heightRatio: CGFloat) {
        if let idx = textCardTrack.entries.firstIndex(where: { $0.id == id }) {
            textCardTrack.entries[idx].widthRatio = widthRatio
            textCardTrack.entries[idx].heightRatio = heightRatio
            markDirty()
        }
    }

    func updateTextCardCornerRadius(id: UUID, cornerRadius: CGFloat) {
        if let idx = textCardTrack.entries.firstIndex(where: { $0.id == id }) {
            textCardTrack.entries[idx].cornerRadius = cornerRadius
            markDirty()
        }
    }

    func updateTextCardStyle(id: UUID, style: TextCardStyle) {
        if let idx = textCardTrack.entries.firstIndex(where: { $0.id == id }) {
            textCardTrack.entries[idx].style = style
            markDirty()
        }
    }

    func updateTextCardTime(id: UUID, startTime: Double, endTime: Double) {
        if let idx = textCardTrack.entries.firstIndex(where: { $0.id == id }) {
            textCardTrack.entries[idx].startTime = startTime
            textCardTrack.entries[idx].endTime = endTime
            markDirty()
        }
    }

    func updateTextCardFadeInOut(id: UUID, fadeInOut: Bool) {
        if let idx = textCardTrack.entries.firstIndex(where: { $0.id == id }) {
            textCardTrack.entries[idx].fadeInOut = fadeInOut
            markDirty()
        }
    }

    func updateTextCardSoundEffect(id: UUID, soundEffect: TextCardSoundEffect) {
        if let idx = textCardTrack.entries.firstIndex(where: { $0.id == id }) {
            textCardTrack.entries[idx].soundEffect = soundEffect
            markDirty()
        }
    }

    // MARK: - 播放頭同步

    func syncPlayheadFromPlayer() {
        timeline.playheadPosition = playback.currentTime
    }

    // MARK: - 專案操作

    func markDirty() {
        isDirty = true
    }

    func saveProject() {
        if let url = currentProjectURL {
            do {
                try ProjectSerializer.save(vm: self, to: url)
                isDirty = false
            } catch {
                debugLog("[Project] 儲存失敗: \(error)")
            }
        } else {
            saveProjectAs()
        }
    }

    func saveProjectAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "lazyed")!]
        panel.nameFieldStringValue = "我的專案.lazyed"
        panel.title = "儲存專案"
        panel.prompt = "儲存"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try ProjectSerializer.save(vm: self, to: url)
            currentProjectURL = url
            isDirty = false
        } catch {
            debugLog("[Project] 另存新檔失敗: \(error)")
        }
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: "lazyed")!]
        panel.title = "開啟專案"
        panel.prompt = "開啟"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadProject(from: url)
    }

    func loadProject(from url: URL) {
        do {
            try ProjectSerializer.load(from: url, into: self)
            currentProjectURL = url
            isDirty = false
            updateEQPreview()
        } catch {
            debugLog("[Project] 開啟專案失敗: \(error)")
        }
    }

    func setupAutoSave() {
        autoSaveTimer?.invalidate()
        guard autoSaveConfig.enabled else { return }

        autoSaveTimer = Timer.scheduledTimer(
            withTimeInterval: autoSaveConfig.intervalSeconds,
            repeats: true
        ) { [weak self] _ in
            guard let self, self.isDirty else { return }
            if let url = self.currentProjectURL {
                do {
                    try ProjectSerializer.save(vm: self, to: url)
                    self.isDirty = false
                    debugLog("[AutoSave] 已自動儲存")
                } catch {
                    debugLog("[AutoSave] 失敗: \(error)")
                }
            } else {
                // 無專案路徑 → 存到自動儲存資料夾
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd_HHmmss"
                let name = "自動儲存_\(formatter.string(from: Date())).lazyed"
                let url = self.autoSaveConfig.folderURL.appendingPathComponent(name)
                do {
                    try ProjectSerializer.save(vm: self, to: url)
                    self.isDirty = false
                    debugLog("[AutoSave] 自動儲存至: \(url.lastPathComponent)")
                } catch {
                    debugLog("[AutoSave] 失敗: \(error)")
                }
            }
        }
    }

    // MARK: - 內部

    /// 上一次的預覽暫存檔 URL（用於清理）
    private var lastFlatPreviewURL: URL?

    /// 重建預覽用 composition（使用代理檔）
    /// 策略：先立即用 composition 替換 player（即時回饋），
    /// 再在背景匯出為單一暫存檔，完成後靜默切換（長片順暢播放）。
    func rebuildComposition() {
        markDirty()
        timelineVM.updateContentWidth(segments: timeline.segments)
        compositionTask?.cancel()
        compositionTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            do {
                let result = try await VideoCompositionBuilder.buildCompositionWithMix(
                    from: timeline.segments,
                    clips: clips,
                    useProxy: true
                )

                // 空 composition 不替換 player item
                guard result.composition.duration.seconds > 0 else { return }
                guard !Task.isCancelled else { return }

                // ── 第一步：立即用 composition 替換 player（即時回饋） ──
                let videoComp = await selectedFilter.makeVideoComposition(
                    for: result.composition,
                    intensity: self.filterIntensity
                )

                // EQ tap 掛載到 composition 音軌
                var immediateMix: AVMutableAudioMix? = nil
                let compAudioTracks = try await result.composition.loadTracks(withMediaType: .audio)
                if let audioTrack = compAudioTracks.first {
                    let tap = AudioEQTap.createTap(context: self.playback.eqTapContext)
                    let mix = AVMutableAudioMix()
                    let params = AVMutableAudioMixInputParameters(track: audioTrack)
                    params.audioTapProcessor = tap
                    // 沿用 volume ramp 設定
                    if let originalMix = result.audioMix {
                        for origParam in originalMix.inputParameters {
                            // 合併 tap 到原始參數（但 AudioMixInputParameters 無法直接合併，
                            // 所以只掛 tap，音量由 audioMix 中的 ramp 處理）
                        }
                    }
                    mix.inputParameters = [params]
                    immediateMix = mix
                }
                // 如果有 volume ramp，優先使用原始 audioMix（含音量調整）
                let activeMix = result.audioMix ?? immediateMix

                let wasPlaying = playback.isPlaying
                let position = timeline.playheadPosition

                playback.replacePlayerItem(
                    with: result.composition,
                    audioMix: activeMix,
                    videoComposition: videoComp
                )

                if position > 0 {
                    playback.seek(to: position)
                }
                if wasPlaying {
                    playback.player.play()
                    playback.isPlaying = true
                }

                // ── 第二步：背景匯出扁平檔，完成後靜默切換 ──
                guard !Task.isCancelled else { return }

                let flatURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("preview_\(UUID().uuidString).mov")

                guard let session = AVAssetExportSession(
                    asset: result.composition,
                    presetName: AVAssetExportPreset960x540
                ) else { return }
                session.outputURL = flatURL
                session.outputFileType = .mov
                if let audioMix = result.audioMix {
                    session.audioMix = audioMix
                }

                await session.export()

                guard session.status == .completed else {
                    debugLog("[Preview] 預覽匯出失敗: \(session.error?.localizedDescription ?? "未知")")
                    return
                }
                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: flatURL)
                    return
                }

                // 清理上一次的暫存檔
                if let oldURL = lastFlatPreviewURL {
                    try? FileManager.default.removeItem(at: oldURL)
                }
                lastFlatPreviewURL = flatURL

                // 用扁平檔靜默替換（記錄當前播放位置與狀態）
                let flatAsset = AVURLAsset(url: flatURL)

                let flatVideoComp = await selectedFilter.makeVideoComposition(
                    for: flatAsset,
                    intensity: self.filterIntensity
                )

                var flatAudioMix: AVMutableAudioMix? = nil
                let flatAudioTracks = try await flatAsset.loadTracks(withMediaType: .audio)
                if let audioTrack = flatAudioTracks.first {
                    let tap = AudioEQTap.createTap(context: self.playback.eqTapContext)
                    let mix = AVMutableAudioMix()
                    let params = AVMutableAudioMixInputParameters(track: audioTrack)
                    params.audioTapProcessor = tap
                    mix.inputParameters = [params]
                    flatAudioMix = mix
                }

                let currentPos = playback.currentTime
                let stillPlaying = playback.isPlaying

                playback.replacePlayerItem(
                    with: flatAsset,
                    audioMix: flatAudioMix,
                    videoComposition: flatVideoComp
                )

                if currentPos > 0 {
                    playback.seek(to: currentPos)
                }
                if stillPlaying {
                    playback.player.play()
                    playback.isPlaying = true
                }
            } catch {
                debugLog("[Preview] Composition 重建失敗：\(error.localizedDescription)")
            }
        }
    }
}
