import SwiftUI

struct MainEditorView: View {
    @Environment(ProjectViewModel.self) var vm

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
        .onKeyPress(.space) {
            vm.playback.togglePlayPause()
            return .handled
        }
        .onKeyPress("a") {
            vm.toolMode = .selection
            return .handled
        }
        .onKeyPress("b") {
            vm.toolMode = .blade
            return .handled
        }
        .onKeyPress(.delete) {
            vm.deleteSelectedSegments()
            return .handled
        }
        .onChange(of: vm.playback.currentTime) {
            vm.syncPlayheadFromPlayer()
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
