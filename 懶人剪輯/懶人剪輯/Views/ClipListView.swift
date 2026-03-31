import SwiftUI

struct ClipListView: View {
    @Bindable var vm: ProjectViewModel
    @State private var selectedSegmentID: UUID?
    @State private var volumeEditSegmentID: UUID?
    @State private var volumeEditValue: Float = 0

    var body: some View {
        VStack(spacing: 0) {
            // 標題列
            HStack {
                Text("素材庫")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(vm.timeline.segments.count) 個片段")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(white: 0.12))

            Divider().background(Color(white: 0.2))

            // 片段列表
            if vm.timeline.segments.isEmpty {
                Spacer()
                Text("尚無素材")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.35))
                Spacer()
            } else {
                List(selection: $selectedSegmentID) {
                    ForEach(vm.timeline.segments) { segment in
                        if let clip = vm.clips[segment.clipID] {
                            segmentRow(segment: segment, clip: clip)
                                .tag(segment.id)
                                .listRowBackground(
                                    selectedSegmentID == segment.id
                                        ? Color(white: 0.22)
                                        : Color(white: 0.13)
                                )
                                .listRowSeparatorTint(Color(white: 0.2))
                                .contextMenu {
                                    segmentContextMenu(segment: segment)
                                }
                        }
                    }
                    .onMove { from, to in
                        vm.reorderSegments(fromOffsets: from, toOffset: to)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: selectedSegmentID) { _, newValue in
                    if let id = newValue {
                        vm.seekToSegment(id)
                    }
                }
                .onDeleteCommand {
                    if let id = selectedSegmentID {
                        vm.deleteSegment(id)
                        selectedSegmentID = nil
                    }
                }
            }
        }
        .frame(width: 240)
        .background(Color(white: 0.1))
        .popover(item: $volumeEditSegmentID) { segmentID in
            volumePopover(segmentID: segmentID)
        }
    }

    // MARK: - 右鍵選單

    @ViewBuilder
    private func segmentContextMenu(segment: ClipSegment) -> some View {
        Button("音量調整...") {
            volumeEditValue = segment.volumeDB
            volumeEditSegmentID = segment.id
        }

        Divider()

        Button("刪除片段") {
            if selectedSegmentID == segment.id {
                selectedSegmentID = nil
            }
            vm.deleteSegment(segment.id)
        }
    }

    // MARK: - 音量調整 Popover

    private func volumePopover(segmentID: UUID) -> some View {
        VStack(spacing: 12) {
            Text("音量調整")
                .font(.headline)

            HStack {
                Text("\(volumeEditValue > 0 ? "+" : "")\(String(format: "%.1f", volumeEditValue)) dB")
                    .font(.system(.title3, design: .monospaced))
                    .frame(width: 80)
            }

            Slider(value: $volumeEditValue, in: -30...30, step: 0.5)
                .frame(width: 200)

            HStack(spacing: 8) {
                ForEach([-6, -3, 0, 3, 6], id: \.self) { db in
                    Button("\(db > 0 ? "+" : "")\(db)") {
                        volumeEditValue = Float(db)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            HStack(spacing: 12) {
                Button("重置") {
                    volumeEditValue = 0
                }
                .controlSize(.small)

                Spacer()

                Button("套用") {
                    vm.setSegmentVolume(segmentID, db: volumeEditValue)
                    volumeEditSegmentID = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    // MARK: - 片段列

    private func segmentRow(segment: ClipSegment, clip: VideoClip) -> some View {
        HStack(spacing: 8) {
            // 代理狀態圖示
            if clip.isGeneratingProxy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            } else if clip.isProxyReady {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "film")
                    .font(.caption2)
                    .foregroundStyle(Color(white: 0.4))
                    .frame(width: 16, height: 16)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(clip.displayName)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 4) {
                    Text(formatDuration(segment.duration))
                        .font(.caption2)
                        .foregroundStyle(Color(white: 0.5))

                    if segment.volumeDB != 0 {
                        Text("\(segment.volumeDB > 0 ? "+" : "")\(String(format: "%.1f", segment.volumeDB))dB")
                            .font(.caption2)
                            .foregroundStyle(segment.volumeDB > 0 ? .orange : .cyan)
                    }
                }
            }

            Spacer()

            // 刪除按鈕
            Button {
                if selectedSegmentID == segment.id {
                    selectedSegmentID = nil
                }
                vm.deleteSegment(segment.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.4))
            }
            .buttonStyle(.plain)
            .help("刪除片段")
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "00:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - UUID Identifiable for popover item binding
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
