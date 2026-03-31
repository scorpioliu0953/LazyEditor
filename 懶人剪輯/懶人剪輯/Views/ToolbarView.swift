import SwiftUI

struct ToolbarView: View {
    @Bindable var vm: ProjectViewModel
    @State private var showSilenceConfig = false
    @State private var showAudioSettings = false
    @State private var showSubtitleSettings = false
    @State private var showAutoSaveSettings = false
    @State private var showFilterPanel = false
    @State private var showTextCardSettings = false

    var body: some View {
        HStack(spacing: 8) {
            // 匯入按鈕
            toolbarButton(icon: "plus.rectangle.on.folder", label: "匯入") {
                vm.showImportPanel()
            }
            .help("匯入影片 (⌘I)")

            toolbarDivider

            // 工具模式切換
            HStack(spacing: 2) {
                toolbarToggle(
                    icon: "cursorarrow",
                    isActive: vm.toolMode == .selection
                ) {
                    vm.toolMode = .selection
                }
                .help("選取工具 (A)")

                toolbarToggle(
                    icon: "scissors",
                    isActive: vm.toolMode == .blade
                ) {
                    vm.toolMode = .blade
                }
                .help("剪刀工具 (B)")
            }

            toolbarDivider

            // 靜音偵測設定
            toolbarButton(icon: "slider.horizontal.3", label: "靜音設定") {
                showSilenceConfig.toggle()
            }
            .popover(isPresented: $showSilenceConfig) {
                SilenceConfigPanel(vm: vm)
            }

            // 一鍵去靜音
            toolbarButton(icon: "waveform.path.ecg", label: "去除靜音") {
                vm.removeAllSilence()
            }
            .disabled(vm.clips.isEmpty)
            .help("一鍵去除所有靜音片段")

            toolbarDivider

            // 音頻設定
            toolbarButton(icon: "speaker.wave.2.fill", label: "音頻") {
                showAudioSettings.toggle()
            }
            .popover(isPresented: $showAudioSettings) {
                AudioSettingsPanel(vm: vm)
            }
            .help("音頻設定（EQ、去雜音、音量平衡）")

            // 字幕設定
            toolbarButton(icon: "captions.bubble", label: "字幕") {
                showSubtitleSettings.toggle()
            }
            .popover(isPresented: $showSubtitleSettings) {
                SubtitleSettingsPanel(vm: vm)
            }
            .help("字幕匯入與設定")

            // 字卡
            toolbarButton(icon: "text.bubble", label: "字卡") {
                showTextCardSettings.toggle()
            }
            .popover(isPresented: $showTextCardSettings) {
                TextCardSettingsPanel(vm: vm)
            }
            .help("文字卡片設定")

            // 濾鏡
            toolbarButton(icon: "camera.filters", label: "濾鏡") {
                showFilterPanel.toggle()
            }
            .popover(isPresented: $showFilterPanel) {
                FilterPanel(vm: vm)
            }
            .help("影片濾鏡效果")

            toolbarDivider

            // 復原
            toolbarButton(icon: "arrow.uturn.backward", label: "復原") {
                vm.undo()
            }
            .disabled(!vm.timeline.canUndo)
            .help("復原 (⌘Z)")

            toolbarDivider

            // 播放控制
            toolbarButton(
                icon: vm.playback.isPlaying ? "pause.fill" : "play.fill",
                label: vm.playback.isPlaying ? "暫停" : "播放"
            ) {
                vm.playback.togglePlayPause()
            }
            .help("播放 / 暫停 (Space)")

            Spacer()

            // 開啟專案
            toolbarButton(icon: "folder", label: "開啟") {
                vm.openProject()
            }
            .help("開啟專案 (⌘O)")

            // 儲存按鈕
            toolbarButton(icon: "square.and.arrow.down", label: "儲存") {
                vm.saveProject()
            }
            .help("儲存專案 (⌘S)")

            toolbarDivider

            // 匯出影片
            Button {
                vm.exportVideo()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12))
                    Text("匯出")
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    vm.timeline.segments.isEmpty
                        ? Color.accentColor.opacity(0.3)
                        : Color.accentColor
                )
                .foregroundStyle(.white)
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .disabled(vm.timeline.segments.isEmpty || vm.exportVM.isExporting)
            .help("匯出影片 + 音訊")

            // (匯出按鈕已包含自動分離音訊)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(white: 0.18))
    }

    // MARK: - 工具列元件

    private func toolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 9))
            }
            .foregroundStyle(Color(white: 0.8))
            .frame(width: 48, height: 36)
        }
        .buttonStyle(.plain)
    }

    private func toolbarToggle(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 32, height: 28)
                .background(isActive ? Color.accentColor.opacity(0.5) : Color.clear)
                .foregroundStyle(isActive ? .white : Color(white: 0.6))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private var toolbarDivider: some View {
        Divider()
            .frame(height: 24)
            .opacity(0.3)
    }
}
