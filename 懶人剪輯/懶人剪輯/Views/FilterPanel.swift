import SwiftUI

struct FilterPanel: View {
    @Bindable var vm: ProjectViewModel

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("影片濾鏡")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(VideoFilterPreset.allCases) { preset in
                    filterCard(preset: preset)
                }
            }

            // 強度滑桿（濾鏡啟用時才顯示）
            if vm.selectedFilter != .none {
                Divider()

                HStack(spacing: 8) {
                    Text("強度")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.7))

                    Slider(value: $vm.filterIntensity, in: 0...1, step: 0.05)
                        .onChange(of: vm.filterIntensity) {
                            vm.updateFilterPreview()
                        }

                    Text("\(Int(vm.filterIntensity * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(white: 0.6))
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .padding()
        .frame(width: 340)
    }

    private func filterCard(preset: VideoFilterPreset) -> some View {
        let isSelected = vm.selectedFilter == preset

        return Button {
            vm.selectedFilter = preset
            vm.rebuildComposition()
        } label: {
            VStack(spacing: 4) {
                // 色彩預覽圓
                let c = preset.iconColor
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        preset == .none
                            ? Color(white: 0.25)
                            : Color(red: c.r, green: c.g, blue: c.b)
                    )
                    .frame(height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .overlay {
                        if preset == .none {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color(white: 0.5))
                        }
                    }

                Text(preset.label)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .white : Color(white: 0.7))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .help(preset.description)
    }
}
