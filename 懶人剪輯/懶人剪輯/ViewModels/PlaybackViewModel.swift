import AVFoundation
import AVKit
import Observation

@Observable
final class PlaybackViewModel {
    var isPlaying = false
    var currentTime: Double = 0

    let player = AVPlayer()
    let eqTapContext = EQTapContext()
    private var timeObserverToken: Any?

    func setupTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(value: 1, timescale: 30) // 30fps
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

    func replacePlayerItem(with composition: AVMutableComposition, audioMix: AVMutableAudioMix? = nil, videoComposition: AVVideoComposition? = nil) {
        let item = AVPlayerItem(asset: composition)
        if let audioMix { item.audioMix = audioMix }
        if let videoComposition { item.videoComposition = videoComposition }
        // 限制解碼解析度為 540p，降低 CPU/GPU 負擔
        item.preferredMaximumResolution = CGSize(width: 960, height: 540)
        // 預載 2 秒緩衝，減少播放卡頓
        item.preferredForwardBufferDuration = 2
        player.replaceCurrentItem(with: item)

        // Debug: 監控播放狀態
        let tracks = composition.tracks
        for t in tracks {
            debugLog("[Player] track: \(t.mediaType.rawValue) segments=\(t.segments.count) naturalSize=\(t.naturalSize)")
        }
        debugLog("[Player] composition naturalSize=\(composition.naturalSize) duration=\(composition.duration.seconds)s")

        setupTimeObserver()
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
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

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
    }
}
