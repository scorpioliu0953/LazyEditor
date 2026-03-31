import SwiftUI

struct AudioSettingsPanel: View {
    @Bindable var vm: ProjectViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("音頻設定")
                    .font(.headline)

                // MARK: - 整體音量
                volumeSection

                Divider()

                // MARK: - EQ
                eqSection

                Divider()

                // MARK: - 一鍵功能
                quickActions

                Divider()

                Text("去雜音 / 音量平衡效果將在匯出時套用，EQ 和整體音量可即時預覽")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(width: 300, height: 520)
    }

    // MARK: - 整體音量

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("整體音量")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(volumeText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Slider(
                    value: $vm.audioSettings.volumeDB,
                    in: -20...20,
                    step: 0.5
                )

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("重置") {
                    vm.audioSettings.volumeDB = 0
                    vm.applyVolumeToPlayback()
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()
            }
        }
        .onChange(of: vm.audioSettings.volumeDB) {
            vm.applyVolumeToPlayback()
        }
    }

    private var volumeText: String {
        let db = vm.audioSettings.volumeDB
        if db > 0 { return "+\(String(format: "%.1f", db)) dB" }
        if db < 0 { return "\(String(format: "%.1f", db)) dB" }
        return "0 dB"
    }

    // MARK: - EQ 等化器

    private var eqSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $vm.audioSettings.eqEnabled) {
                Text("等化器 (EQ)")
                    .font(.subheadline.weight(.medium))
            }
            .toggleStyle(.checkbox)
            .onChange(of: vm.audioSettings.eqEnabled) {
                vm.updateEQPreview()
            }

            if vm.audioSettings.eqEnabled {
                // 預設選擇
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("場景：")
                            .font(.caption)
                        Picker("", selection: Binding(
                            get: { vm.audioSettings.eqPreset },
                            set: {
                                vm.audioSettings.applyPreset($0)
                                vm.updateEQPreview()
                            }
                        )) {
                            ForEach(EQPreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        .frame(width: 160)
                    }

                    Text(vm.audioSettings.eqPreset.description)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                // 頻段滑桿
                VStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { i in
                        eqBandRow(index: i)
                    }
                }
            }
        }
    }

    private func eqBandRow(index: Int) -> some View {
        HStack(spacing: 6) {
            Text(AudioSettings.bandLabels[index])
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 28, alignment: .trailing)
                .foregroundStyle(.secondary)

            Slider(
                value: $vm.audioSettings.bands[index],
                in: -12...12,
                step: 0.5
            )
            .onChange(of: vm.audioSettings.bands[index]) {
                vm.audioSettings.eqPreset = .custom
                vm.updateEQPreview()
            }

            Text(bandGainText(vm.audioSettings.bands[index]))
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }

    private func bandGainText(_ gain: Float) -> String {
        if gain > 0 { return "+\(String(format: "%.0f", gain))" }
        return String(format: "%.0f", gain)
    }

    // MARK: - 一鍵功能

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 去雜音
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $vm.audioSettings.noiseReductionEnabled) {
                    HStack {
                        Image(systemName: "waveform.badge.minus")
                        Text("去除雜音")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .toggleStyle(.checkbox)

                if vm.audioSettings.noiseReductionEnabled {
                    HStack {
                        Text("強度：")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: $vm.audioSettings.noiseReductionStrength,
                            in: 0.1...1.0,
                            step: 0.1
                        )
                        Text(String(format: "%.0f%%", vm.audioSettings.noiseReductionStrength * 100))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 32)
                    }
                    Text("移除低頻噪音（空調聲、電流嗡聲）")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            // 音量平衡
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $vm.audioSettings.levelingEnabled) {
                    HStack {
                        Image(systemName: "waveform.and.magnifyingglass")
                        Text("音量平衡")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .toggleStyle(.checkbox)

                if vm.audioSettings.levelingEnabled {
                    HStack {
                        Text("強度：")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: $vm.audioSettings.levelingAmount,
                            in: 0.1...1.0,
                            step: 0.1
                        )
                        Text(String(format: "%.0f%%", vm.audioSettings.levelingAmount * 100))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 32)
                    }
                    Text("壓縮動態範圍，讓音量更均勻一致")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
