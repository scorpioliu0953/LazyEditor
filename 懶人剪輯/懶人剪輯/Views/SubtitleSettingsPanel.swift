import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SubtitleSettingsPanel: View {
    @Bindable var vm: ProjectViewModel
    @State private var selectedTrack: Int = 0 // 0 = primary, 1 = secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("字幕設定")
                .font(.headline)

            // 字幕軌選擇
            Picker("字幕軌", selection: $selectedTrack) {
                Text("第一語言 (S1)").tag(0)
                Text("第二語言 (S2)").tag(1)
            }
            .pickerStyle(.segmented)

            let track = selectedTrack == 0 ? vm.primarySubtitleTrack : vm.secondarySubtitleTrack

            // 匯入 SRT
            HStack {
                Button("匯入 SRT 字幕⋯") {
                    importSRT(for: track)
                }

                if !track.entries.isEmpty {
                    Text("\(track.entries.count) 條字幕")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("清除") {
                        track.entries.removeAll()
                    }
                    .foregroundStyle(.red)
                }
            }

            Divider()

            // 語言選擇
            HStack {
                Text("語言")
                Picker("", selection: Bindable(track).language) {
                    ForEach(SubtitleLanguage.allCases) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
                .frame(width: 120)
            }

            // 顯示切換
            Toggle("顯示字幕", isOn: Bindable(track).isVisible)

            Divider()

            // 樣式預設
            Text("樣式預設")
                .font(.subheadline.bold())

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 6) {
                ForEach(SubtitleStylePreset.allCases) { preset in
                    Button {
                        track.settings.applyPreset(preset)
                    } label: {
                        Text(preset.label)
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(Color(white: 0.2))
                            .foregroundStyle(.white)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // 自訂字型
            Text("字型設定")
                .font(.subheadline.bold())

            HStack {
                Text("字型")
                Spacer()
                FontPickerButton(fontName: Bindable(track.settings).fontName)
            }

            // 字體大小
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("字體大小")
                    Spacer()
                    // 快速大小按鈕
                    HStack(spacing: 4) {
                        ForEach([
                            ("小", 0.035),
                            ("中", 0.055),
                            ("大", 0.075),
                            ("特大", 0.095)
                        ], id: \.0) { label, ratio in
                            Button(label) {
                                track.settings.fontSizeRatio = ratio
                            }
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                abs(track.settings.fontSizeRatio - ratio) < 0.005
                                    ? Color.accentColor.opacity(0.6)
                                    : Color(white: 0.25)
                            )
                            .foregroundStyle(.white)
                            .cornerRadius(3)
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack(spacing: 4) {
                    Text("小")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.5))
                    Slider(
                        value: Bindable(track.settings).fontSizeRatio,
                        in: 0.02...0.12,
                        step: 0.005
                    )
                    Text("大")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.5))
                    Text(String(format: "%.1f%%", track.settings.fontSizeRatio * 100))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(white: 0.6))
                        .frame(width: 36, alignment: .trailing)
                }
            }

            ColorPicker("文字顏色", selection: Bindable(track.settings).textColor)
            ColorPicker("描邊顏色", selection: Bindable(track.settings).strokeColor)

            HStack {
                Text("描邊粗細")
                Slider(
                    value: Bindable(track.settings).strokeWidth,
                    in: 0...4,
                    step: 0.2
                )
                Text(String(format: "%.1f", track.settings.strokeWidth))
                    .font(.caption.monospacedDigit())
                    .frame(width: 30)
            }

            HStack {
                Text("文字間距")
                Slider(
                    value: Bindable(track.settings).letterSpacing,
                    in: 0...10,
                    step: 0.5
                )
                Text(String(format: "%.1f", track.settings.letterSpacing))
                    .font(.caption.monospacedDigit())
                    .frame(width: 30)
            }

            HStack {
                Text("垂直位置")
                Slider(
                    value: Bindable(track.settings).verticalPositionRatio,
                    in: 0.5...0.95,
                    step: 0.01
                )
                Text(String(format: "%.0f%%", track.settings.verticalPositionRatio * 100))
                    .font(.caption.monospacedDigit())
                    .frame(width: 40)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func importSRT(for track: SubtitleTrack) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: "srt")!]
        panel.title = "匯入 SRT 字幕"
        panel.prompt = "匯入"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let entries = try SRTParser.parse(url: url)
            track.entries = entries
        } catch {
            debugLog("[Subtitle] SRT 匯入失敗: \(error.localizedDescription)")
        }
    }
}

// MARK: - 字型選取按鈕

struct FontPickerButton: View {
    @Binding var fontName: String

    var body: some View {
        Button(fontName) {
            showFontPanel()
        }
        .font(.system(size: 12))
    }

    private func showFontPanel() {
        let fontManager = NSFontManager.shared
        let font = NSFont(name: fontName, size: 14) ?? NSFont.systemFont(ofSize: 14)
        fontManager.setSelectedFont(font, isMultiple: false)
        fontManager.target = FontPickerDelegate.shared
        fontManager.action = #selector(FontPickerDelegate.changeFont(_:))
        FontPickerDelegate.shared.onFontChange = { newFont in
            fontName = newFont.fontName
        }
        fontManager.orderFrontFontPanel(nil)
    }
}

private class FontPickerDelegate: NSObject {
    static let shared = FontPickerDelegate()
    var onFontChange: ((NSFont) -> Void)?

    @objc func changeFont(_ sender: NSFontManager?) {
        guard let fontManager = sender else { return }
        let newFont = fontManager.convert(NSFont.systemFont(ofSize: 14))
        onFontChange?(newFont)
    }
}
