import AVFoundation
import Foundation

/// 合成短音效 WAV 檔案並提供播放 / 匯出用 URL
final class SoundEffectGenerator {
    static let shared = SoundEffectGenerator()

    private let sampleRate: Double = 44100
    private var cache: [TextCardSoundEffect: URL] = [:]
    private var player: AVAudioPlayer?

    // MARK: - 播放試聽

    func play(_ effect: TextCardSoundEffect) {
        guard effect != .none else { return }
        guard let url = urlForEffect(effect) else { return }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            debugLog("[SoundEffect] 播放失敗: \(error)")
        }
    }

    // MARK: - 取得音效檔 URL（lazy 生成）

    func urlForEffect(_ effect: TextCardSoundEffect) -> URL? {
        guard effect != .none else { return nil }
        if let cached = cache[effect] { return cached }

        let url = generateWAV(for: effect)
        cache[effect] = url
        return url
    }

    // MARK: - WAV 合成

    private func generateWAV(for effect: TextCardSoundEffect) -> URL? {
        let duration: Double
        let generator: (AVAudioPCMBuffer, Double) -> Void

        switch effect {
        case .none:
            return nil
        case .pop:
            duration = 0.12
            generator = generatePop
        case .ding:
            duration = 0.3
            generator = generateDing
        case .whoosh:
            duration = 0.25
            generator = generateWhoosh
        case .click:
            duration = 0.08
            generator = generateClick
        case .chime:
            duration = 0.3
            generator = generateChime
        case .bubble:
            duration = 0.15
            generator = generateBubble
        case .swoosh:
            duration = 0.2
            generator = generateSwoosh
        case .bell:
            duration = 0.3
            generator = generateBell
        case .tap:
            duration = 0.1
            generator = generateTap
        case .tone:
            duration = 0.2
            generator = generateTone
        }

        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        generator(buffer, duration)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sfx_\(effect.rawValue).wav")

        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            return url
        } catch {
            debugLog("[SoundEffect] WAV 寫入失敗: \(error)")
            return nil
        }
    }

    // MARK: - 各音效波形

    private func generatePop(_ buffer: AVAudioPCMBuffer, _ duration: Double) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let freq = 800.0 * (1.0 - t / duration * 0.5)
            let envelope = max(0, 1.0 - t / duration)
            data[i] = Float(sin(2.0 * .pi * freq * t) * envelope * envelope * 0.7)
        }
    }

    private func generateDing(_ buffer: AVAudioPCMBuffer, _ duration: Double) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let envelope = exp(-t * 8.0)
            let wave = sin(2.0 * .pi * 1200.0 * t) * 0.5 + sin(2.0 * .pi * 2400.0 * t) * 0.3
            data[i] = Float(wave * envelope * 0.6)
        }
    }

    private func generateWhoosh(_ buffer: AVAudioPCMBuffer, _ duration: Double) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let progress = t / duration
            let envelope = sin(.pi * progress) // bell curve
            let noise = Double.random(in: -1...1)
            let filtered = noise * envelope * 0.4
            data[i] = Float(filtered)
        }
    }

    private func generateClick(_ buffer: AVAudioPCMBuffer, _ duration: Double) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let envelope = max(0, 1.0 - t / duration) * max(0, 1.0 - t / duration)
            let wave = sin(2.0 * .pi * 3000.0 * t) + sin(2.0 * .pi * 1500.0 * t) * 0.5
            data[i] = Float(wave * envelope * 0.5)
        }
    }

    private func generateChime(_ buffer: AVAudioPCMBuffer, _ duration: Double) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let envelope = exp(-t * 6.0)
            let wave = sin(2.0 * .pi * 880.0 * t) * 0.4
                + sin(2.0 * .pi * 1320.0 * t) * 0.3
                + sin(2.0 * .pi * 1760.0 * t) * 0.2
            data[i] = Float(wave * envelope * 0.6)
        }
    }

    private func generateBubble(_ buffer: AVAudioPCMBuffer, _ duration: Double) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let freq = 600.0 + 400.0 * sin(2.0 * .pi * 8.0 * t)
            let envelope = max(0, 1.0 - t / duration)
            data[i] = Float(sin(2.0 * .pi * freq * t) * envelope * 0.5)
        }
    }

    private func generateSwoosh(_ buffer: AVAudioPCMBuffer, _ duration: Double) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let progress = t / duration
            let envelope = sin(.pi * progress)
            let freq = 200.0 + 2000.0 * progress
            let wave = sin(2.0 * .pi * freq * t) * 0.3
            let noise = Double.random(in: -1...1) * 0.2
            data[i] = Float((wave + noise) * envelope * 0.5)
        }
    }

    private func generateBell(_ buffer: AVAudioPCMBuffer, _ duration: Double) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let envelope = exp(-t * 5.0)
            let wave = sin(2.0 * .pi * 523.0 * t) * 0.4
                + sin(2.0 * .pi * 1047.0 * t) * 0.3
                + sin(2.0 * .pi * 1568.0 * t) * 0.15
                + sin(2.0 * .pi * 2093.0 * t) * 0.1
            data[i] = Float(wave * envelope * 0.6)
        }
    }

    private func generateTap(_ buffer: AVAudioPCMBuffer, _ duration: Double) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let envelope = max(0, 1.0 - t / duration)
            let e3 = envelope * envelope * envelope
            let wave = sin(2.0 * .pi * 2000.0 * t) * 0.6
                + Double.random(in: -1...1) * 0.3
            data[i] = Float(wave * e3 * 0.5)
        }
    }

    private func generateTone(_ buffer: AVAudioPCMBuffer, _ duration: Double) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let fadeIn = min(1.0, t / 0.02)
            let fadeOut = min(1.0, (duration - t) / 0.02)
            let envelope = fadeIn * fadeOut
            let wave = sin(2.0 * .pi * 660.0 * t) * 0.5
                + sin(2.0 * .pi * 990.0 * t) * 0.25
            data[i] = Float(wave * envelope * 0.5)
        }
    }
}
