import AppKit
import Observation
import UniformTypeIdentifiers

@Observable
final class ExportViewModel {
    var isExporting = false
    var exportProgress: Float = 0
    var exportError: String?

    func showSavePanel() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = Constants.defaultExportFilename
        panel.title = "匯出影片"
        panel.prompt = "匯出"

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func showSavePanelForAudio() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Audio, .mp3]
        panel.nameFieldStringValue = "懶人剪輯_輸出.m4a"
        panel.title = "匯出音頻"
        panel.prompt = "匯出"

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func reset() {
        isExporting = false
        exportProgress = 0
        exportError = nil
    }
}
