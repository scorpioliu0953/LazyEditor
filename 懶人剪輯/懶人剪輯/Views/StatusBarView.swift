import SwiftUI
import CoreMedia

struct StatusBarView: View {
    let vm: ProjectViewModel

    var body: some View {
        HStack(spacing: 12) {
            // 工具模式指示
            HStack(spacing: 4) {
                Image(systemName: vm.toolMode.systemImage)
                    .font(.system(size: 10))
                Text(vm.toolMode.label)
                    .font(.system(size: 10))
            }
            .foregroundStyle(Color(white: 0.5))

            Divider().frame(height: 12).opacity(0.3)

            // 當前時間 / 總時長
            Text(currentTimeText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.7))

            Spacer()

            // 匯出進度
            if vm.exportVM.isExporting {
                HStack(spacing: 6) {
                    ProgressView(value: Double(vm.exportVM.exportProgress))
                        .frame(width: 100)
                        .tint(.accentColor)
                    Text("\(Int(vm.exportVM.exportProgress * 100))%")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.6))
                }
            }

            if let error = vm.exportVM.exportError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }

            // 代理檔狀態
            if vm.proxyGeneratingCount > 0 {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("產生預覽檔⋯")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.5))
                }
            } else if allProxiesReady {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8))
                    Text("代理預覽")
                        .font(.system(size: 10))
                }
                .foregroundStyle(Color.green.opacity(0.7))
            }

            Divider().frame(height: 12).opacity(0.3)

            // 選取數量
            if vm.timeline.selectedSegmentIDs.count > 1 {
                Text("已選取 \(vm.timeline.selectedSegmentIDs.count) 個片段")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.6))

                Divider().frame(height: 12).opacity(0.3)
            }

            // 未儲存指示
            if vm.isDirty {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text("未儲存")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }

                Divider().frame(height: 12).opacity(0.3)
            }

            // 播放器狀態（debug）
            Text(vm.playback.playerStatusText)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(playerStatusColor)

            Divider().frame(height: 12).opacity(0.3)

            // 片段數量
            Text("\(vm.timeline.segments.count) 個片段")
                .font(.system(size: 10))
                .foregroundStyle(Color(white: 0.5))

            Divider().frame(height: 12).opacity(0.3)

            Text("v2.5")
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.3))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Color(white: 0.14))
    }

    private var playerStatusColor: Color {
        switch vm.playback.playerStatusText {
        case "playing": .green
        case "paused", "ended": Color(white: 0.5)
        case "buffering": .yellow
        case "failed": .red
        default: Color(white: 0.35)
        }
    }

    private var allProxiesReady: Bool {
        !vm.clips.isEmpty && vm.clips.values.allSatisfy(\.isProxyReady)
    }

    private var currentTimeText: String {
        let current = CMTime.from(seconds: vm.playback.currentTime).displayString
        let total = CMTime.from(seconds: vm.timeline.totalDuration).displayString
        return "\(current) / \(total)"
    }
}
