import AVFoundation

/// Plays short sine-wave beeps for audio feedback (start, stop, complete).
public final class BeepPlayer {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let sampleRate: Double = 44_100

    public init() {
        engine.attach(playerNode)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    private func ensureRunning() {
        if !engine.isRunning {
            try? engine.start()
        }
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    /// Play a sine-wave beep at the given frequency and duration.
    public func play(frequency: Float, duration: Float = 0.09) {
        ensureRunning()

        let frameCount = Int(Float(sampleRate) * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let data = buffer.floatChannelData?[0] else { return }
        for i in 0..<frameCount {
            let t = Float(i) / Float(sampleRate)
            data[i] = sin(2 * .pi * frequency * t) * 0.35
        }
        // Fade out last 20%
        let fadeLen = max(1, frameCount / 5)
        for i in 0..<fadeLen {
            let idx = frameCount - fadeLen + i
            data[idx] *= Float(fadeLen - i) / Float(fadeLen)
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// 880 Hz — recording started
    public func beepStart() { play(frequency: 880) }
    /// 550 Hz — recording stopped
    public func beepStop() { play(frequency: 550) }
    /// 1100 Hz, short — transcription complete
    public func beepDone() { play(frequency: 1100, duration: 0.06) }
}
