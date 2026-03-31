import AVFoundation

@Observable
final class VideoClip: Identifiable {
    let id: UUID
    let url: URL
    let asset: AVURLAsset
    var duration: Double = 0
    var waveformData: [Float]?

    // MARK: - Proxy（代理預覽檔）

    var proxyURL: URL?
    var proxyAsset: AVURLAsset?
    var isProxyReady: Bool = false
    var isGeneratingProxy: Bool = false

    /// 取得用於預覽的 asset（優先使用 proxy）
    var previewAsset: AVURLAsset {
        proxyAsset ?? asset
    }

    /// 檔名（不含副檔名）
    var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }

    /// 時長格式化為 MM:SS
    var durationText: String {
        guard duration > 0 else { return "00:00" }
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
        self.asset = AVURLAsset(url: url)
    }

    /// 清除代理暫存檔
    func cleanupProxy() {
        if let proxyURL {
            try? FileManager.default.removeItem(at: proxyURL)
        }
    }
}
