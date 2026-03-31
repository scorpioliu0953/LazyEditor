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
        track.settings.verticalPositionRatio = 0.92
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

            let segment = ClipSegment(
                clipID: clip.id,
                startTime: 0,
                endTime: 0
            )
            timeline.segments.append(segment)

            let segmentIndex = timeline.segments.count - 1

            Task {
                defer {
                    if accessGranted { url.stopAccessingSecurityScopedResource() }
                }

                let duration = try await clip.asset.load(.duration)
                clip.duration = duration.seconds

                if segmentIndex < timeline.segments.count {
                    let old = timeline.segments[segmentIndex]
                    timeline.segments[segmentIndex] = ClipSegment(
                        clipID: old.clipID,
                        startTime: old.startTime,
                        endTime: duration.seconds
                    )
                }

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

        Task {
            do {
                let result = try await VideoCompositionBuilder.buildCompositionWithMix(
                    from: timeline.segments,
                    clips: clips
                )
                let composition = result.composition

                let exportVM = self.exportVM

                // 暫存處理後音檔路徑（音訊匯出後才清理）
                var processedAudioURL: URL? = nil

                if needsAudioProcessing {
                    // 離線處理音頻
                    let audioURL = try await AudioProcessor.processAudio(
                        from: composition,
                        settings: settingsSnapshot
                    ) { progress in
                        Task { @MainActor in
                            exportVM.exportProgress = progress * 0.4
                        }
                    }
                    processedAudioURL = audioURL

                    // 替換 composition 中的音軌為處理後的音頻
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
                        // 以影片軌長度為準，避免處理後音檔長度不一致
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

                    if let videoComp = await VideoFilterPreset.makeExportVideoComposition(
                        for: composition,
                        filter: filterPreset,
                        intensity: filterIntensityVal,
                        primaryTrack: primarySnap,
                        secondaryTrack: secondarySnap,
                        textCardTrack: textCardSnap
                    ) {
                        try await VideoExporter.exportWithFilter(
                            composition: composition,
                            videoComposition: videoComp,
                            audioMix: nil,
                            to: outputURL
                        ) { progress in
                            Task { @MainActor in
                                exportVM.exportProgress = 0.4 + progress * 0.6
                            }
                        }
                    } else {
                        try await VideoExporter.export(
                            composition: composition,
                            to: outputURL
                        ) { progress in
                            Task { @MainActor in
                                exportVM.exportProgress = 0.4 + progress * 0.6
                            }
                        }
                    }
                } else {
                    if let videoComp = await VideoFilterPreset.makeExportVideoComposition(
                        for: composition,
                        filter: filterPreset,
                        intensity: filterIntensityVal,
                        primaryTrack: primarySnap,
                        secondaryTrack: secondarySnap,
                        textCardTrack: textCardSnap
                    ) {
                        try await VideoExporter.exportWithFilter(
                            composition: composition,
                            videoComposition: videoComp,
                            audioMix: result.audioMix,
                            to: outputURL
                        ) { progress in
                            Task { @MainActor in
                                exportVM.exportProgress = progress * 1.0
                            }
                        }
                    } else {
                        try await VideoExporter.export(
                            composition: composition,
                            to: outputURL,
                            audioMix: result.audioMix
                        ) { progress in
                            Task { @MainActor in
                                exportVM.exportProgress = progress * 1.0
                            }
                        }
                    }
                }

                // MP4 匯出完成 → 立即結束進度條
                exportVM.exportProgress = 1.0
                exportVM.isExporting = false

                // M4A/WAV 匯出在背景 fire-and-forget，不阻塞 UI
                let audioMixForExport = needsAudioProcessing ? nil : result.audioMix
                let m4aURL = outputURL.deletingPathExtension().appendingPathExtension("m4a")
                let wavURL = outputURL.deletingPathExtension().appendingPathExtension("wav")
                let capturedProcessedAudioURL = processedAudioURL

                Task.detached(priority: .utility) {
                    do {
                        try await VideoExporter.exportAudio(
                            composition: composition,
                            audioMix: audioMixForExport,
                            to: m4aURL
                        ) { _ in }
                        debugLog("[Export] M4A 匯出完成: \(m4aURL.lastPathComponent)")

                        try await VideoExporter.exportAudio(
                            composition: composition,
                            audioMix: audioMixForExport,
                            to: wavURL
                        ) { _ in }
                        debugLog("[Export] WAV 匯出完成: \(wavURL.lastPathComponent)")
                    } catch {
                        debugLog("[Export] 音訊匯出失敗: \(error)")
                    }

                    // 清理暫存檔（在音訊匯出之後，因為 composition 還需要讀取）
                    if let url = capturedProcessedAudioURL {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            } catch {
                exportVM.isExporting = false
                exportVM.exportError = error.localizedDescription
                debugLog("[Export] 影片匯出失敗: \(error)")
            }
        }
    }

    func exportAudioMP3() {
        guard let outputURL = exportVM.showSavePanelForAudio() else { return }

        exportVM.isExporting = true
        exportVM.exportProgress = 0
        exportVM.exportError = nil

        Task {
            do {
                let result = try await VideoCompositionBuilder.buildCompositionWithMix(
                    from: timeline.segments,
                    clips: clips
                )

                let exportVM = self.exportVM

                try await VideoExporter.exportAudio(
                    composition: result.composition,
                    audioMix: result.audioMix,
                    to: outputURL
                ) { progress in
                    Task { @MainActor in
                        exportVM.exportProgress = progress
                    }
                }

                exportVM.isExporting = false
            } catch {
                exportVM.isExporting = false
                exportVM.exportError = error.localizedDescription
                debugLog("[Export] 音訊匯出失敗: \(error)")
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

    /// 重建預覽用 composition（使用代理檔）
    func rebuildComposition() {
        markDirty()
        compositionTask?.cancel()
        compositionTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }

            do {
                let tap = AudioEQTap.createTap(context: self.playback.eqTapContext)
                let result = try await VideoCompositionBuilder.buildCompositionWithMix(
                    from: timeline.segments,
                    clips: clips,
                    useProxy: true,
                    audioTap: tap
                )

                // 濾鏡：建立 AVVideoComposition
                let videoComp = await selectedFilter.makeVideoComposition(
                    for: result.composition,
                    intensity: self.filterIntensity
                )

                playback.replacePlayerItem(
                    with: result.composition,
                    audioMix: result.audioMix,
                    videoComposition: videoComp
                )
                // 替換 player item 後恢復播放頭位置
                let position = timeline.playheadPosition
                if position > 0 {
                    playback.seek(to: position)
                }
            } catch {
                print("Composition 重建失敗：\(error.localizedDescription)")
            }
        }
    }
}
