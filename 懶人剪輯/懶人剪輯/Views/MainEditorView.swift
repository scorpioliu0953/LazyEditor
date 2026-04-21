import SwiftUI

struct MainEditorView: View {
    @Environment(ProjectViewModel.self) var vm
    @FocusState private var isMainFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 工具列
            ToolbarView(vm: vm)

            // 影片預覽 + 素材列表
            HStack(spacing: 0) {
                Group {
                    if vm.timeline.segments.isEmpty {
                        emptyStateView
                    } else {
                        ZStack {
                            VideoPreviewView(player: vm.playback.player)
                            SubtitleOverlayView(vm: vm)
                            TextCardOverlayView(vm: vm)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.08))
                .overlay { ImportDropOverlay(vm: vm) }

                ClipListView(vm: vm)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 時間軸（片段軌 + 音頻軌）
            TimelineView(vm: vm)

            // 狀態列
            StatusBarView(vm: vm)
        }
        .background(Color(white: 0.1))
        .focusable()
        .focused($isMainFocused)
        .onAppear { isMainFocused = true }
        .onKeyPress(.space) {
            guard !vm.isEditingTextCard else { return .ignored }
            vm.playback.togglePlayPause()
            return .handled
        }
        .onKeyPress("a") {
            guard !vm.isEditingTextCard else { return .ignored }
            vm.toolMode = .selection
            return .handled
        }
        .onKeyPress("b") {
            guard !vm.isEditingTextCard else { return .ignored }
            vm.toolMode = .blade
            return .handled
        }
        .onKeyPress(.delete) {
            guard !vm.isEditingTextCard else { return .ignored }
            vm.deleteSelectedSegments()
            return .handled
        }
        .onKeyPress(.deleteForward) {
            guard !vm.isEditingTextCard else { return .ignored }
            vm.deleteSelectedSegments()
            return .handled
        }
        .onChange(of: vm.playback.currentTime) {
            vm.syncPlayheadFromPlayer()
        }
        .onChange(of: vm.timeline.selectedSegmentIDs) {
            // 選取片段後重新取得焦點，確保 Delete 鍵可用
            isMainFocused = true
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundStyle(Color(white: 0.3))
            Text("拖放影片檔案或按下「匯入」開始")
                .font(.title3)
                .foregroundStyle(Color(white: 0.45))
            Text("支援 MP4、MOV、M4V 格式")
                .font(.caption)
                .foregroundStyle(Color(white: 0.3))
        }
    }
}
