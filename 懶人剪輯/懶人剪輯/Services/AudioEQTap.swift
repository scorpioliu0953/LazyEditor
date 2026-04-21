import AVFoundation
import MediaToolbox
import os

// MARK: - BiquadFilter（二階 IIR 濾波器）

struct BiquadFilter {
    // 係數
    var b0: Float = 1, b1: Float = 0, b2: Float = 0
    var a1: Float = 0, a2: Float = 0
    // 狀態
    var x1: Float = 0, x2: Float = 0
    var y1: Float = 0, y2: Float = 0

    mutating func process(_ input: Float) -> Float {
        let output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = input
        y2 = y1; y1 = output
        return output
    }

    // Audio EQ Cookbook — Low Shelf (80 Hz), S=1
    static func lowShelf(freq: Float, gainDB: Float, sampleRate: Float) -> BiquadFilter {
        let A = powf(10, gainDB / 40)
        let w0 = 2 * Float.pi * freq / sampleRate
        let cosw0 = cosf(w0)
        let sinw0 = sinf(w0)
        // S=1: (A + 1/A)*(1/S - 1) + 2 = 2
        let alpha = sinw0 / 2 * sqrtf(2.0)
        let twoSqrtAAlpha = 2 * sqrtf(A) * alpha

        let a0 = (A + 1) + (A - 1) * cosw0 + twoSqrtAAlpha
        var f = BiquadFilter()
        f.b0 = A * ((A + 1) - (A - 1) * cosw0 + twoSqrtAAlpha) / a0
        f.b1 = 2 * A * ((A - 1) - (A + 1) * cosw0) / a0
        f.b2 = A * ((A + 1) - (A - 1) * cosw0 - twoSqrtAAlpha) / a0
        f.a1 = -2 * ((A - 1) + (A + 1) * cosw0) / a0
        f.a2 = ((A + 1) + (A - 1) * cosw0 - twoSqrtAAlpha) / a0
        return f
    }

    // Audio EQ Cookbook — High Shelf (12 kHz), S=1
    static func highShelf(freq: Float, gainDB: Float, sampleRate: Float) -> BiquadFilter {
        let A = powf(10, gainDB / 40)
        let w0 = 2 * Float.pi * freq / sampleRate
        let cosw0 = cosf(w0)
        let sinw0 = sinf(w0)
        let alpha = sinw0 / 2 * sqrtf(2.0)
        let twoSqrtAAlpha = 2 * sqrtf(A) * alpha

        let a0 = (A + 1) - (A - 1) * cosw0 + twoSqrtAAlpha
        var f = BiquadFilter()
        f.b0 = A * ((A + 1) + (A - 1) * cosw0 + twoSqrtAAlpha) / a0
        f.b1 = -2 * A * ((A - 1) + (A + 1) * cosw0) / a0
        f.b2 = A * ((A + 1) + (A - 1) * cosw0 - twoSqrtAAlpha) / a0
        f.a1 = 2 * ((A - 1) - (A + 1) * cosw0) / a0
        f.a2 = ((A + 1) - (A - 1) * cosw0 - twoSqrtAAlpha) / a0
        return f
    }

    // Audio EQ Cookbook — Peaking EQ (250 Hz, 1 kHz, 4 kHz)
    static func peaking(freq: Float, gainDB: Float, bandwidth: Float, sampleRate: Float) -> BiquadFilter {
        let A = powf(10, gainDB / 40)
        let w0 = 2 * Float.pi * freq / sampleRate
        let cosw0 = cosf(w0)
        let sinw0 = sinf(w0)
        let alpha = sinw0 * sinhf(logf(2) / 2 * bandwidth * w0 / sinw0)

        let a0 = 1 + alpha / A
        var f = BiquadFilter()
        f.b0 = (1 + alpha * A) / a0
        f.b1 = -2 * cosw0 / a0
        f.b2 = (1 - alpha * A) / a0
        f.a1 = -2 * cosw0 / a0
        f.a2 = (1 - alpha / A) / a0
        return f
    }
}

// MARK: - EQTapContext（跨執行緒共享的 EQ 狀態）

final class EQTapContext: @unchecked Sendable {
    private var lock = os_unfair_lock()

    private var _eqEnabled: Bool = false
    private var _bandGains: [Float] = [0, 0, 0, 0, 0]
    private var _needsRecalc: Bool = true

    // 僅由音訊執行緒存取（透過 C callback 繞過 actor isolation）
    var filters: [[BiquadFilter]] = []  // [channel][band]
    var sampleRate: Double = 44100
    var processCallCount: Int = 0

    /// 主執行緒呼叫：更新 EQ 參數
    func updateSettings(enabled: Bool, bands: [Float]) {
        os_unfair_lock_lock(&lock)
        _eqEnabled = enabled
        _bandGains = bands
        _needsRecalc = true
        os_unfair_lock_unlock(&lock)
        debugLog("[EQTap] updateSettings: enabled=\(enabled), bands=\(bands)")
    }

    /// 音訊執行緒呼叫：讀取 EQ 參數（C callback 繞過 actor isolation）
    func readSettings() -> (enabled: Bool, bands: [Float], needsRecalc: Bool) {
        os_unfair_lock_lock(&lock)
        let result = (_eqEnabled, _bandGains, _needsRecalc)
        _needsRecalc = false
        os_unfair_lock_unlock(&lock)
        return result
    }
}

// MARK: - AudioEQTap

struct AudioEQTap {
    static func createTap(context: EQTapContext) -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque()),
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )

        #if compiler(>=6.2)
        // Swift 6.2+ (Xcode 16.4+): MTAudioProcessingTapCreate 回復為 MTAudioProcessingTap?
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tap
        )
        if status == noErr {
            debugLog("[EQTap] 建立成功: tap=\(tap != nil)")
        } else {
            debugLog("[EQTap] 建立失敗: status=\(status)")
        }
        guard status == noErr else { return nil }
        return tap
        #else
        // Swift 6.1 (Xcode 16.3): MTAudioProcessingTapCreate 使用 Unmanaged
        var unmanagedTap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &unmanagedTap
        )
        if status == noErr {
            debugLog("[EQTap] 建立成功: tap=\(unmanagedTap != nil)")
        } else {
            debugLog("[EQTap] 建立失敗: status=\(status)")
        }
        guard status == noErr, let unmanagedTap else { return nil }
        return unmanagedTap.takeRetainedValue()
        #endif
    }
}

// MARK: - Tap Callbacks

private let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
    tapStorageOut.pointee = clientInfo
    debugLog("[EQTap] init callback")
}

private let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
    debugLog("[EQTap] finalize callback")
    let storage = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<EQTapContext>.fromOpaque(storage).release()
}

private let tapPrepare: MTAudioProcessingTapPrepareCallback = { tap, maxFrames, format in
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<EQTapContext>.fromOpaque(storage).takeUnretainedValue()

    let desc = format.pointee
    context.sampleRate = desc.mSampleRate
    let channels = Int(desc.mChannelsPerFrame)

    context.filters = (0..<channels).map { _ in
        [BiquadFilter](repeating: BiquadFilter(), count: 5)
    }

    let isFloat = (desc.mFormatFlags & kAudioFormatFlagIsFloat) != 0
    let isPacked = (desc.mFormatFlags & kAudioFormatFlagIsPacked) != 0
    let isNonInterleaved = (desc.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
    debugLog("[EQTap] prepared: \(channels)ch, \(desc.mSampleRate)Hz, bitsPerCh=\(desc.mBitsPerChannel), isFloat=\(isFloat), isPacked=\(isPacked), isNonInterleaved=\(isNonInterleaved), maxFrames=\(maxFrames)")
}

private let tapUnprepare: MTAudioProcessingTapUnprepareCallback = { _ in
    debugLog("[EQTap] unprepare callback")
}

private let tapProcess: MTAudioProcessingTapProcessCallback = { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
    // 取得來源音訊
    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
    guard status == noErr else {
        debugLog("[EQTap] getSourceAudio failed: \(status)")
        return
    }

    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<EQTapContext>.fromOpaque(storage).takeUnretainedValue()

    // 每 500 次記錄一次（約每 10 秒），避免日誌過多
    context.processCallCount += 1
    if context.processCallCount <= 3 || context.processCallCount % 500 == 0 {
        let bufCount = UnsafeMutableAudioBufferListPointer(bufferListInOut).count
        debugLog("[EQTap] process #\(context.processCallCount): frames=\(numberFrames), buffers=\(bufCount)")
    }

    let settings = context.readSettings()
    guard settings.enabled else { return }

    // 參數變更時重算係數（保留濾波器狀態避免爆音）
    if settings.needsRecalc {
        let sr = Float(context.sampleRate)
        let freqs = AudioSettings.bandFrequencies
        let gains = settings.bands

        debugLog("[EQTap] recalc: sr=\(sr), gains=\(gains)")

        for ch in 0..<context.filters.count {
            for band in 0..<5 {
                let state = (
                    context.filters[ch][band].x1, context.filters[ch][band].x2,
                    context.filters[ch][band].y1, context.filters[ch][band].y2
                )

                let newFilter: BiquadFilter
                switch band {
                case 0:  newFilter = .lowShelf(freq: freqs[0], gainDB: gains[0], sampleRate: sr)
                case 4:  newFilter = .highShelf(freq: freqs[4], gainDB: gains[4], sampleRate: sr)
                default: newFilter = .peaking(freq: freqs[band], gainDB: gains[band], bandwidth: 1.0, sampleRate: sr)
                }

                context.filters[ch][band] = newFilter
                context.filters[ch][band].x1 = state.0
                context.filters[ch][band].x2 = state.1
                context.filters[ch][band].y1 = state.2
                context.filters[ch][band].y2 = state.3
            }
        }
    }

    // 逐 sample 通過 5 組 biquad 濾波器
    let bufferList = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    for ch in 0..<min(bufferList.count, context.filters.count) {
        guard let data = bufferList[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
        let frameCount = Int(numberFramesOut.pointee)

        for i in 0..<frameCount {
            var sample = data[i]
            for band in 0..<5 {
                sample = context.filters[ch][band].process(sample)
            }
            data[i] = sample
        }
    }
}
