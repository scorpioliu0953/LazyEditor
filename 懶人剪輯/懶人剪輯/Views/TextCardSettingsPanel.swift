import SwiftUI

struct TextCardSettingsPanel: View {
    @Bindable var vm: ProjectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("字卡設定")
                .font(.headline)

            // 新增字卡
            Button {
                let currentTime = vm.playback.currentTime
                let entry = TextCardEntry(
                    startTime: currentTime,
                    endTime: currentTime + 3.0,
                    text: "文字卡片"
                )
                vm.textCardTrack.addEntry(entry)
                vm.selectedTextCardID = entry.id
                vm.markDirty()
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("新增字卡")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.8))
                .foregroundStyle(.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            if !vm.textCardTrack.entries.isEmpty {
                HStack {
                    Text("\(vm.textCardTrack.entries.count) 張字卡")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清除全部") {
                        vm.textCardTrack.entries.removeAll()
                        vm.selectedTextCardID = nil
                        vm.markDirty()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }

            Divider()

            // 樣式選擇格
            Text("樣式")
                .font(.subheadline.bold())

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 6) {
                ForEach(TextCardStyle.allCases) { style in
                    Button {
                        if let id = vm.selectedTextCardID {
                            vm.updateTextCardStyle(id: id, style: style)
                        }
                    } label: {
                        stylePreview(style)
                    }
                    .buttonStyle(.plain)
                }
            }

            // 選中字卡的設定
            if let selectedID = vm.selectedTextCardID,
               let idx = vm.textCardTrack.entries.firstIndex(where: { $0.id == selectedID }) {
                let card = vm.textCardTrack.entries[idx]

                Divider()

                Text("選取的字卡")
                    .font(.subheadline.bold())

                // 文字輸入
                VStack(alignment: .leading, spacing: 4) {
                    Text("文字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: Binding(
                        get: { card.text },
                        set: { vm.updateTextCardText(id: selectedID, text: $0) }
                    ))
                    .font(.system(size: 12))
                    .frame(height: 50)
                    .border(Color(white: 0.3))
                }

                // 時間設定
                HStack(spacing: 8) {
                    VStack(alignment: .leading) {
                        Text("開始").font(.system(size: 9)).foregroundStyle(.secondary)
                        TextField("", text: Binding(
                            get: { formatSeconds(card.startTime) },
                            set: {
                                if let t = parseSeconds($0) {
                                    vm.updateTextCardTime(id: selectedID, startTime: t, endTime: card.endTime)
                                }
                            }
                        ))
                        .font(.system(size: 10, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    }
                    VStack(alignment: .leading) {
                        Text("結束").font(.system(size: 9)).foregroundStyle(.secondary)
                        TextField("", text: Binding(
                            get: { formatSeconds(card.endTime) },
                            set: {
                                if let t = parseSeconds($0) {
                                    vm.updateTextCardTime(id: selectedID, startTime: card.startTime, endTime: t)
                                }
                            }
                        ))
                        .font(.system(size: 10, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    }
                }

                // 縮放
                HStack {
                    Text("大小")
                    Slider(
                        value: Binding(
                            get: { card.scale },
                            set: { vm.updateTextCardScale(id: selectedID, scale: $0) }
                        ),
                        in: 0.3...3.0,
                        step: 0.1
                    )
                    Text(String(format: "%.1fx", card.scale))
                        .font(.caption.monospacedDigit())
                        .frame(width: 35)
                }

                // 刪除
                Button {
                    vm.textCardTrack.removeEntry(id: selectedID)
                    vm.selectedTextCardID = nil
                    vm.markDirty()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("刪除字卡")
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - 樣式預覽格

    private func stylePreview(_ style: TextCardStyle) -> some View {
        let isActive = vm.selectedTextCardID.flatMap { id in
            vm.textCardTrack.entries.first { $0.id == id }?.style
        } == style

        return VStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: style.cornerRadius * 0.3)
                    .fill(style.backgroundColor != .clear ? style.backgroundColor : Color(white: 0.2))
                    .frame(height: 28)
                Text("Aa")
                    .font(.system(size: 12, weight: style.fontWeight == .heavy ? .heavy : .medium))
                    .foregroundStyle(style.textColor)
            }
            Text(style.label)
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.7))
        }
        .padding(4)
        .background(isActive ? Color.accentColor.opacity(0.3) : Color(white: 0.15))
        .cornerRadius(6)
        .overlay(
            isActive
                ? RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 1.5)
                : nil
        )
    }

    // MARK: - 時間格式

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
