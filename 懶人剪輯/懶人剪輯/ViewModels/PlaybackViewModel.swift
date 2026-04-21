import AVFoundation
import AVKit
import Observation
import os

private let playerLog = Logger(subsystem: "SC.------", category: "player")

@Observable
final class PlaybackViewModel {
    var isPlaying = false
    var currentTime: Double = 0
    /// 用於 UI 顯示播放器狀態（debug 用）
    var playerStatusText: String = "idle"

    let player: AVPlayer = {
        let p = AVPlayer()
        // 關閉自動緩衝評估：Composition 由本機多段片段組成，
        // 預設的「評估緩衝率」機制會誤判為網路串流不穩而反覆暫停
        p.automaticallyWaitsToMinimizeStalling = false
        return p
    }()
    let eqTapContext = EQTapContext()
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var stallCount: Int = 0

    func setupTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(value: 1, timescale: 10) // 10fps
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds
        }
    }

    func removeTimeObserver() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    func replacePlayerItem(with asset: AVAsset, audioMix: AVMutableAudioMix? = nil, videoComposition: AVVideoComposition? = nil) {
        let item = AVPlayerItem(asset: asset)
        if let audioMix { item.audioMix = audioMix }
        if let videoComposition { item.videoComposition = videoComposition }
        // 限制解碼解析度為 540p，降低 CPU/GPU 負擔
        item.preferredMaximumResolution = CGSize(width: 960, height: 540)
        item.preferredForwardBufferDuration = 2
        player.replaceCurrentItem(with: item)
        stallCount = 0

        // Debug
        Task {
            let duration = try? await asset.load(.duration)
            playerLog.info("[Player] asset duration=\(duration?.seconds ?? 0)s")
        }

        setupTimeObserver()
        observePlayerItemEnd(item: item)
        observePlayerItemStatus(item: item)
        observeTimeControlStatus()
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // 如果播放頭在結尾附近（< 0.1s），回到開頭再播放
            if let item = player.currentItem {
                let duration = item.duration
                if duration.isValid && !duration.isIndefinite {
                    let remaining = CMTimeSubtract(duration, player.currentTime())
                    if CMTimeGetSeconds(remaining) < 0.1 {
                        player.seek(to: .zero)
                    }
                }
            }
            // 如果 playerItem 失敗了，不嘗試播放
            if player.currentItem?.status == .failed {
                playerLog.error("[Player] togglePlay: item 已失敗，無法播放")
                isPlaying = false
                return
            }
            player.play()
            isPlaying = true
        }
        playerLog.debug("[Player] togglePlayPause → isPlaying=\(self.isPlaying)")
    }

    func seek(to seconds: Double) {
        let time = CMTime.from(seconds: seconds)
        // 初剪用：允許 ±0.1 秒容差，避免從 keyframe 逐幀解碼
        let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
        currentTime = seconds
    }

    func stop() {
        player.pause()
        isPlaying = false
    }

    // MARK: - 播放狀態監聽

    /// 監聽播放到結尾通知，自動重置 isPlaying
    private func observePlayerItemEnd(item: AVPlayerItem) {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isPlaying = false
            self.playerStatusText = "ended"
            playerLog.info("[Player] 播放到結尾")
        }
    }

    /// 監聽 playerItem 狀態（偵測失敗）
    private func observePlayerItemStatus(item: AVPlayerItem) {
        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch item.status {
                case .failed:
                    self.isPlaying = false
                    self.playerStatusText = "failed"
                    let errMsg = item.error?.localizedDescription ?? "未知錯誤"
                    playerLog.error("[Player] playerItem 失敗: \(errMsg)")
                    if let err = item.error as NSError? {
                        playerLog.error("[Player] 錯誤詳情: domain=\(err.domain) code=\(err.code) userInfo=\(err.userInfo.description)")
                    }
                case .readyToPlay:
                    self.playerStatusText = "ready"
                    playerLog.info("[Player] playerItem 就緒")
                case .unknown:
                    self.playerStatusText = "loading"
                    playerLog.debug("[Player] playerItem 載入中")
                @unknown default:
                    break
                }
            }
        }
    }

    /// 監聽播放器的 timeControlStatus（偵測卡頓/意外暫停）
    private func observeTimeControlStatus() {
        timeControlObservation?.invalidate()
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new, .old]) { [weak self] player, change in
            DispatchQueue.main.async {
                guard let self else { return }
                let status = player.timeControlStatus
                switch status {
                case .paused:
                    // 如果 isPlaying 為 true 但播放器實際已暫停 → 狀態脫節
                    if self.isPlaying {
                        playerLog.warning("[Player] 播放器意外暫停（isPlaying 仍為 true），同步狀態")
                        self.isPlaying = false
                    }
                    self.playerStatusText = "paused"

                case .playing:
                    self.playerStatusText = "playing"

                case .waitingToPlayAtSpecifiedRate:
                    self.stallCount += 1
                    let reason = player.reasonForWaitingToPlay?.rawValue ?? "unknown"
                    playerLog.warning("[Player] 播放卡頓 #\(self.stallCount): reason=\(reason) time=\(player.currentTime().seconds)s")
                    self.playerStatusText = "buffering"

                    // 如果是缺少資料導致的等待，且卡頓次數過多，嘗試 seek 恢復
                    if self.stallCount >= 3 {
                        let currentSec = player.currentTime().seconds
                        playerLog.warning("[Player] 連續卡頓 \(self.stallCount) 次，嘗試 seek 恢復")
                        let seekTime = CMTime.from(seconds: currentSec)
                        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600))
                        self.stallCount = 0
                    }

                @unknown default:
                    break
                }
            }
        }
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        statusObservation?.invalidate()
        timeControlObservation?.invalidate()
    }
}
