import SwiftUI
import AppKit

struct TimelineView: View {
    @Bindable var vm: ProjectViewModel

    private var totalTimelineHeight: CGFloat {
        var h = Constants.timeRulerHeight + Constants.segmentTrackHeight + Constants.audioTrackHeight
        if !vm.primarySubtitleTrack.entries.isEmpty {
            h += Constants.subtitleTrackHeight
        }
        if !vm.secondarySubtitleTrack.entries.isEmpty {
            h += Constants.subtitleTrackHeight
        }
        if !vm.textCardTrack.entries.isEmpty {
            h += Constants.textCardTrackHeight
        }
        return h
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { outerGeo in
                let availableWidth = outerGeo.size.width - Constants.trackLabelWidth
                let totalWidth = max(availableWidth, vm.timelineVM.cachedContentWidth + 60)

                HStack(spacing: 0) {
                    trackLabels

                    NativeHScrollView(contentWidth: totalWidth) {
                        timelineContent
                            .frame(width: totalWidth)
                    }
                }
            }
        }
        .frame(height: totalTimelineHeight)
        .background(Constants.timelineBg)
        .gesture(magnificationGesture)
    }

    // MARK: - 左側軌道標籤

    private var trackLabels: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: Constants.timeRulerHeight)

            Text("V")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.5))
                .frame(width: Constants.trackLabelWidth, height: Constants.segmentTrackHeight)
                .background(Constants.trackLabelBg)

            Text("A")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.5))
                .frame(width: Constants.trackLabelWidth, height: Constants.audioTrackHeight)
                .background(Constants.trackLabelBg)

            if !vm.primarySubtitleTrack.entries.isEmpty {
                Text("S1")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Constants.subtitleS1Color)
                    .frame(width: Constants.trackLabelWidth, height: Constants.subtitleTrackHeight)
                    .background(Constants.trackLabelBg)
            }

            if !vm.secondarySubtitleTrack.entries.isEmpty {
                Text("S2")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Constants.subtitleS2Color)
                    .frame(width: Constants.trackLabelWidth, height: Constants.subtitleTrackHeight)
                    .background(Constants.trackLabelBg)
            }

            if !vm.textCardTrack.entries.isEmpty {
                Text("TC")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Constants.textCardTrackColor)
                    .frame(width: Constants.trackLabelWidth, height: Constants.textCardTrackHeight)
                    .background(Constants.trackLabelBg)
            }
        }
        .frame(width: Constants.trackLabelWidth)
    }

    // MARK: - 時間軸主內容

    private var timelineContent: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                timeRuler
                    .frame(height: Constants.timeRulerHeight)

                segmentTrack
                    .frame(height: Constants.segmentTrackHeight)

                audioTrack
                    .frame(height: Constants.audioTrackHeight)

                if !vm.primarySubtitleTrack.entries.isEmpty {
                    SubtitleTrackView(
                        track: vm.primarySubtitleTrack,
                        trackIndex: 0,
                        vm: vm,
                        color: Constants.subtitleS1Color
                    )
                    .frame(height: Constants.subtitleTrackHeight)
                }

                if !vm.secondarySubtitleTrack.entries.isEmpty {
                    SubtitleTrackView(
                        track: vm.secondarySubtitleTrack,
                        trackIndex: 1,
                        vm: vm,
                        color: Constants.subtitleS2Color
                    )
                    .frame(height: Constants.subtitleTrackHeight)
                }

                if !vm.textCardTrack.entries.isEmpty {
                    TextCardTrackView(
                        track: vm.textCardTrack,
                        vm: vm,
                        color: Constants.textCardTrackColor
                    )
                    .frame(height: Constants.textCardTrackHeight)
                }
            }

            TimelinePlayheadOverlay(vm: vm, totalHeight: totalTimelineHeight)

            if vm.toolMode == .blade, let bladeX = vm.timelineVM.bladeHoverX {
                BladeIndicatorLine(
                    xPosition: bladeX,
                    height: totalTimelineHeight
                )
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                if vm.toolMode == .blade {
                    vm.timelineVM.bladeHoverX = location.x
                }
            case .ended:
                vm.timelineVM.bladeHoverX = nil
            }
        }
        .cursor(vm.toolMode == .blade ? .crosshair : .arrow)
        .simultaneousGesture(
            SpatialTapGesture()
                .onEnded { value in
                    let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                    handleTimelineTap(at: value.location, modifiers: modifiers)
                }
        )
    }

    // MARK: - 時間尺規

    private var timeRuler: some View {
        Canvas { context, size in
            let pps = vm.timelineVM.zoomScale
            let totalSeconds = Int(size.width / pps) + 1

            for sec in 0...totalSeconds {
                let x = CGFloat(sec) * pps

                var tick = Path()
                tick.move(to: CGPoint(x: x, y: size.height - 8))
                tick.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(tick, with: .color(Constants.rulerTick), lineWidth: 1)

                let showLabel = (pps >= 60) ? true : (sec % 5 == 0)
                if showLabel {
                    let minutes = sec / 60
                    let secs = sec % 60
                    let text = String(format: "%d:%02d", minutes, secs)
                    context.draw(
                        Text(text)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Constants.rulerText),
                        at: CGPoint(x: x + 2, y: size.height - 16),
                        anchor: .leading
                    )
                }

                if pps >= 40 {
                    let halfX = x + pps * 0.5
                    var halfTick = Path()
                    halfTick.move(to: CGPoint(x: halfX, y: size.height - 4))
                    halfTick.addLine(to: CGPoint(x: halfX, y: size.height))
                    context.stroke(halfTick, with: .color(Constants.rulerTick.opacity(0.5)), lineWidth: 0.5)
                }
            }
        }
        .background(Constants.rulerBg)
        .drawingGroup(opaque: true)
    }

    // MARK: - 片段軌道（V）

    private var segmentTrack: some View {
        ZStack(alignment: .leading) {
            Constants.trackBg

            LazyHStack(spacing: Constants.segmentSpacing) {
                ForEach(vm.timeline.segments) { segment in
                    let clip = vm.clips[segment.clipID]
                    let width = vm.timelineVM.segmentWidth(duration: segment.duration)
                    let range = vm.timelineVM.waveformSampleRange(for: segment)
                    let name = clip?.url.deletingPathExtension().lastPathComponent ?? "片段"

                    ClipSegmentView(
                        segment: segment,
                        clipName: name,
                        waveformData: clip?.waveformData,
                        isSelected: vm.timeline.isSelected(segment.id),
                        width: width,
                        sampleRange: range
                    )
                    .drawingGroup()
                }
            }
        }
    }

    // MARK: - 音頻軌道（A）

    private var audioTrack: some View {
        ZStack(alignment: .leading) {
            Constants.audioSegmentFill.opacity(0.3)

            LazyHStack(spacing: Constants.segmentSpacing) {
                ForEach(vm.timeline.segments) { segment in
                    let clip = vm.clips[segment.clipID]
                    let width = vm.timelineVM.segmentWidth(duration: segment.duration)
                    let range = vm.timelineVM.waveformSampleRange(for: segment)

                    audioSegmentCell(segment: segment, clip: clip, width: width, sampleRange: range)
                        .drawingGroup()
                }
            }
        }
    }

    private func audioSegmentCell(segment: ClipSegment, clip: VideoClip?, width: CGFloat, sampleRange: Range<Int>) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Constants.segmentCornerRadius)
                .fill(Constants.audioSegmentFill)

            if let data = clip?.waveformData {
                let start = max(0, sampleRange.lowerBound)
                let end = min(data.count, sampleRange.upperBound)
                if start < end {
                    WaveformView(
                        samples: data[start..<end],
                        color: Constants.waveformColor,
                        silenceThreshold: vm.silenceConfig.linearThreshold
                    )
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
            }

            // 選取的音頻片段也顯示高亮邊框
            if vm.timeline.isSelected(segment.id) {
                RoundedRectangle(cornerRadius: Constants.segmentCornerRadius)
                    .strokeBorder(Constants.segmentSelectedBorder.opacity(0.6), lineWidth: 1.5)
            }
        }
        .frame(width: width, height: Constants.audioTrackHeight)
    }

    // MARK: - 手勢

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                vm.timelineVM.zoomScale = Constants.defaultPixelsPerSecond * value.magnification
                vm.timelineVM.clampZoom()
                vm.timelineVM.updateContentWidth(segments: vm.timeline.segments)
            }
    }

    private func handleTimelineTap(at location: CGPoint, modifiers: NSEvent.ModifierFlags) {
        let x = location.x
        let y = location.y
        let isShift = modifiers.contains(.shift)
        let isCommand = modifiers.contains(.command)

        // 尺規區域 → 定位播放
        if y < Constants.timeRulerHeight {
            vm.seekTimeline(to: x)
            return
        }

        let isInSegmentTrack = y < Constants.timeRulerHeight + Constants.segmentTrackHeight
        var accX: CGFloat = 0

        for segment in vm.timeline.segments {
            let segWidth = vm.timelineVM.segmentWidth(duration: segment.duration)

            if x >= accX && x < accX + segWidth {
                let localX = x - accX
                let fraction = localX / segWidth

                switch vm.toolMode {
                case .selection:
                    // 在片段軌或音頻軌都支援選取
                    if isInSegmentTrack || !isShift && !isCommand {
                        vm.selectSegment(id: segment.id, shift: isShift, command: isCommand)
                    }

                    // 定位播放頭
                    let localTime = segment.duration * Double(fraction)
                    var elapsed: Double = 0
                    for s in vm.timeline.segments {
                        if s.id == segment.id { break }
                        elapsed += s.duration
                    }
                    vm.seekTimeline(to: vm.timelineVM.timeToX(elapsed + localTime))

                case .blade:
                    let localTime = segment.duration * Double(fraction)
                    vm.bladeAt(segmentID: segment.id, localTime: localTime)
                }
                return
            }
            accX += segWidth + Constants.segmentSpacing
        }

        // 點擊空白區域
        if !isShift && !isCommand {
            vm.timeline.clearSelection()
        }
        vm.seekTimeline(to: x)
    }
}

// MARK: - 播放頭覆蓋層（獨立 struct，隔離 playheadPosition 追蹤）

private struct TimelinePlayheadOverlay: View {
    let vm: ProjectViewModel
    let totalHeight: CGFloat

    private var playheadXPosition: CGFloat {
        let position = vm.timeline.playheadPosition
        var elapsed: Double = 0
        var x: CGFloat = 0

        for (i, segment) in vm.timeline.segments.enumerated() {
            let segEnd = elapsed + segment.duration
            if position <= segEnd {
                let localTime = position - elapsed
                x += CGFloat(localTime) * vm.timelineVM.zoomScale
                return x
            }
            x += vm.timelineVM.segmentWidth(duration: segment.duration) + Constants.segmentSpacing
            elapsed = segEnd

            if i == vm.timeline.segments.count - 1 {
                x += CGFloat(position - segEnd) * vm.timelineVM.zoomScale
            }
        }

        return x
    }

    var body: some View {
        PlayheadView(height: totalHeight)
            .offset(x: playheadXPosition - 5)
            .allowsHitTesting(false)
    }
}

// MARK: - 字幕軌道

struct SubtitleTrackView: View {
    let track: SubtitleTrack
    let trackIndex: Int
    @Bindable var vm: ProjectViewModel
    let color: Color

    @State private var editingEntryID: UUID?
    @State private var popoverAnchorX: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            color.opacity(0.15)

            // 字幕片段（純視覺，不處理手勢）
            ForEach(track.entries) { entry in
                let x = vm.timelineVM.timeToX(entry.startTime)
                let width = vm.timelineVM.segmentWidth(duration: entry.duration)

                RoundedRectangle(cornerRadius: Constants.subtitleEntryCornerRadius)
                    .fill(color.opacity(0.6))
                    .frame(width: max(width, 4), height: Constants.subtitleTrackHeight - 8)
                    .overlay(
                        Text(entry.text)
                            .font(.system(size: 9))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 3)
                        , alignment: .leading
                    )
                    .offset(x: x, y: 4)
                    .allowsHitTesting(false)
            }

            // 隱形 popover 錨點（跟隨雙擊位置）
            Color.clear
                .frame(width: 1, height: 1)
                .offset(x: popoverAnchorX, y: Constants.subtitleTrackHeight / 2)
                .popover(isPresented: Binding(
                    get: { editingEntryID != nil },
                    set: { if !$0 { editingEntryID = nil } }
                )) {
                    if let entryID = editingEntryID,
                       let entry = track.entries.first(where: { $0.id == entryID }) {
                        SubtitleEditPopover(
                            entry: entry,
                            trackIndex: trackIndex,
                            vm: vm
                        )
                    }
                }
        }
        .contentShape(Rectangle())
        .highPriorityGesture(
            SpatialTapGesture(count: 2)
                .onEnded { value in
                    let x = value.location.x
                    for entry in track.entries {
                        let entryX = vm.timelineVM.timeToX(entry.startTime)
                        let entryWidth = vm.timelineVM.segmentWidth(duration: entry.duration)
                        if x >= entryX && x <= entryX + max(entryWidth, 4) {
                            popoverAnchorX = entryX + max(entryWidth, 4) / 2
                            editingEntryID = entry.id
                            return
                        }
                    }
                }
        )
    }
}

// MARK: - 字幕編輯 Popover

private struct SubtitleEditPopover: View {
    let entry: SubtitleEntry
    let trackIndex: Int
    @Bindable var vm: ProjectViewModel

    @State private var editText: String = ""
    @State private var editStart: String = ""
    @State private var editEnd: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("編輯字幕")
                .font(.headline)

            TextEditor(text: $editText)
                .font(.system(size: 13))
                .frame(width: 250, height: 60)
                .border(Color(white: 0.3))

            HStack {
                Text("開始")
                TextField("", text: $editStart)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                Text("結束")
                TextField("", text: $editEnd)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
            }
            .font(.system(size: 11))

            HStack {
                Spacer()
                Button("確定") {
                    let start = parseSeconds(editStart) ?? entry.startTime
                    let end = parseSeconds(editEnd) ?? entry.endTime
                    vm.updateSubtitleEntry(
                        trackIndex: trackIndex,
                        entryID: entry.id,
                        text: editText,
                        startTime: start,
                        endTime: end
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear {
            editText = entry.text
            editStart = formatSeconds(entry.startTime)
            editEnd = formatSeconds(entry.endTime)
        }
    }

    private func formatSeconds(_ s: Double) -> String {
        let h = Int(s) / 3600
        let m = (Int(s) % 3600) / 60
        let sec = s - Double(h * 3600 + m * 60)
        return String(format: "%02d:%02d:%06.3f", h, m, sec)
    }

    private func parseSeconds(_ str: String) -> Double? {
        let parts = str.components(separatedBy: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }
}

// MARK: - 字卡軌道

struct TextCardTrackView: View {
    let track: TextCardTrack
    @Bindable var vm: ProjectViewModel
    let color: Color

    @State private var editingEntryID: UUID?
    @State private var popoverAnchorX: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            color.opacity(0.15)

            ForEach(track.entries) { entry in
                TextCardEntryView(
                    entry: entry,
                    vm: vm,
                    color: color,
                    onDoubleTap: { anchorX in
                        popoverAnchorX = anchorX
                        editingEntryID = entry.id
                    }
                )
            }

            Color.clear
                .frame(width: 1, height: 1)
                .offset(x: popoverAnchorX, y: Constants.textCardTrackHeight / 2)
                .popover(isPresented: Binding(
                    get: { editingEntryID != nil },
                    set: { if !$0 { editingEntryID = nil } }
                )) {
                    if let entryID = editingEntryID,
                       let entry = track.entries.first(where: { $0.id == entryID }) {
                        TextCardEditPopover(entry: entry, vm: vm)
                    }
                }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 可拖曳的字卡條目

private struct TextCardEntryView: View {
    let entry: TextCardEntry
    @Bindable var vm: ProjectViewModel
    let color: Color
    let onDoubleTap: (CGFloat) -> Void

    private let edgeHandleWidth: CGFloat = 5
    private let minDuration: Double = 0.1

    @State private var dragMode: DragMode = .none
    @State private var dragStartTime: Double = 0
    @State private var dragEndTime: Double = 0

    private enum DragMode {
        case none, moveAll, trimLeft, trimRight
    }

    private var isSelected: Bool {
        vm.selectedTextCardID == entry.id
    }

    var body: some View {
        let x = vm.timelineVM.timeToX(dragMode != .none ? dragStartTime : entry.startTime)
        let duration = (dragMode != .none ? dragEndTime : entry.endTime) - (dragMode != .none ? dragStartTime : entry.startTime)
        let width = max(vm.timelineVM.segmentWidth(duration: duration), 4)
        let height: CGFloat = Constants.textCardTrackHeight - 8

        ZStack {
            // 主體
            RoundedRectangle(cornerRadius: Constants.subtitleEntryCornerRadius)
                .fill(color.opacity(isSelected ? 0.9 : 0.6))
                .overlay(
                    Text(entry.text)
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                    , alignment: .leading
                )

            // 左邊緣 handle
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.white.opacity(isSelected ? 0.3 : 0.001))
                    .frame(width: edgeHandleWidth)
                    .cursor(.resizeLeftRight)
                    .gesture(trimLeftGesture)
                Spacer()
                Rectangle()
                    .fill(Color.white.opacity(isSelected ? 0.3 : 0.001))
                    .frame(width: edgeHandleWidth)
                    .cursor(.resizeLeftRight)
                    .gesture(trimRightGesture)
            }

            // 中間拖曳區
            Rectangle()
                .fill(Color.clear)
                .padding(.horizontal, edgeHandleWidth)
                .contentShape(Rectangle())
                .cursor(.openHand)
                .gesture(moveGesture)
        }
        .frame(width: width, height: height)
        .offset(x: x, y: 4)
        .onTapGesture {
            vm.selectedTextCardID = entry.id
        }
        .onTapGesture(count: 2) {
            let entryX = vm.timelineVM.timeToX(entry.startTime)
            let entryW = vm.timelineVM.segmentWidth(duration: entry.duration)
            onDoubleTap(entryX + max(entryW, 4) / 2)
        }
    }

    // MARK: - 整體移動

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragMode == .none {
                    dragMode = .moveAll
                    dragStartTime = entry.startTime
                    dragEndTime = entry.endTime
                    vm.selectedTextCardID = entry.id
                }
                let deltaTime = vm.timelineVM.xToTime(value.translation.width)
                let duration = entry.endTime - entry.startTime
                var newStart = entry.startTime + deltaTime
                newStart = max(0, newStart)
                dragStartTime = newStart
                dragEndTime = newStart + duration
            }
            .onEnded { _ in
                vm.updateTextCardTime(id: entry.id, startTime: dragStartTime, endTime: dragEndTime)
                dragMode = .none
            }
    }

    // MARK: - 左邊緣拖曳（調整開始時間）

    private var trimLeftGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragMode == .none {
                    dragMode = .trimLeft
                    dragStartTime = entry.startTime
                    dragEndTime = entry.endTime
                    vm.selectedTextCardID = entry.id
                }
                let deltaTime = vm.timelineVM.xToTime(value.translation.width)
                var newStart = entry.startTime + deltaTime
                newStart = max(0, newStart)
                newStart = min(newStart, entry.endTime - minDuration)
                dragStartTime = newStart
                dragEndTime = entry.endTime
            }
            .onEnded { _ in
                vm.updateTextCardTime(id: entry.id, startTime: dragStartTime, endTime: dragEndTime)
                dragMode = .none
            }
    }

    // MARK: - 右邊緣拖曳（調整結束時間）

    private var trimRightGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragMode == .none {
                    dragMode = .trimRight
                    dragStartTime = entry.startTime
                    dragEndTime = entry.endTime
                    vm.selectedTextCardID = entry.id
                }
                let deltaTime = vm.timelineVM.xToTime(value.translation.width)
                var newEnd = entry.endTime + deltaTime
                newEnd = max(entry.startTime + minDuration, newEnd)
                dragStartTime = entry.startTime
                dragEndTime = newEnd
            }
            .onEnded { _ in
                vm.updateTextCardTime(id: entry.id, startTime: dragStartTime, endTime: dragEndTime)
                dragMode = .none
            }
    }
}

private struct TextCardEditPopover: View {
    let entry: TextCardEntry
    @Bindable var vm: ProjectViewModel

    @State private var editText: String = ""
    @State private var editStart: String = ""
    @State private var editEnd: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("編輯字卡")
                .font(.headline)

            TextEditor(text: $editText)
                .font(.system(size: 13))
                .frame(width: 250, height: 60)
                .border(Color(white: 0.3))

            HStack {
                Text("開始")
                TextField("", text: $editStart)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                Text("結束")
                TextField("", text: $editEnd)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
            }
            .font(.system(size: 11))

            HStack {
                Spacer()
                Button("確定") {
                    let start = parseSeconds(editStart) ?? entry.startTime
                    let end = parseSeconds(editEnd) ?? entry.endTime
                    vm.updateTextCardText(id: entry.id, text: editText)
                    vm.updateTextCardTime(id: entry.id, startTime: start, endTime: end)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear {
            editText = entry.text
            editStart = formatSeconds(entry.startTime)
            editEnd = formatSeconds(entry.endTime)
        }
    }

    private func formatSeconds(_ s: Double) -> String {
        let h = Int(s) / 3600
        let m = (Int(s) % 3600) / 60
        let sec = s - Double(h * 3600 + m * 60)
        return String(format: "%02d:%02d:%06.3f", h, m, sec)
    }

    private func parseSeconds(_ str: String) -> Double? {
        let parts = str.components(separatedBy: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }
}

// MARK: - 剪刀標示線

private struct BladeIndicatorLine: View {
    let xPosition: CGFloat
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(Constants.bladeLineColor)
            .frame(width: 1.5, height: height)
            .overlay {
                Rectangle()
                    .fill(Constants.bladeLineColor.opacity(0.3))
                    .frame(width: 5, height: height)
            }
            .offset(x: xPosition - 0.75)
            .allowsHitTesting(false)
    }
}

// MARK: - 原生 NSScrollView 包裝（取代 SwiftUI ScrollView，達到 FCP 級絲滑捲動）

private struct NativeHScrollView<Content: View>: NSViewRepresentable {
    let contentWidth: CGFloat
    let content: Content

    init(contentWidth: CGFloat, @ViewBuilder content: () -> Content) {
        self.contentWidth = contentWidth
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.hasHorizontalScroller = true
        sv.hasVerticalScroller = false
        sv.drawsBackground = false
        sv.scrollerStyle = .overlay
        sv.horizontalScrollElasticity = .allowed
        sv.usesPredominantAxisScrolling = true
        sv.automaticallyAdjustsContentInsets = false
        sv.contentInsets = .init()

        // 啟用圖層支援 → Core Animation GPU 合成
        sv.wantsLayer = true
        sv.contentView.wantsLayer = true
        sv.contentView.layerContentsRedrawPolicy = .onSetNeedsDisplay

        let hosting = NSHostingView(rootView: content)
        hosting.wantsLayer = true
        sv.documentView = hosting

        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let hosting = sv.documentView as? NSHostingView<Content> else { return }
        hosting.rootView = content

        let h = max(sv.contentView.bounds.height, 1)
        let w = max(contentWidth, sv.contentView.bounds.width)
        let newSize = NSSize(width: w, height: h)
        if hosting.frame.size != newSize {
            hosting.frame.size = newSize
        }
    }
}

// MARK: - 游標輔助

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
