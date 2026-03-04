import AVFoundation
import Accelerate

/// Records audio from the microphone, detects silence, returns Float32 PCM at 16 kHz mono.
final class AudioRecorder {
    static let sampleRate: Double = 16_000
    private let engine = AVAudioEngine()
    private var buffer: [Float] = []
    private let bufferLock = NSLock()

    private var speechDetected = false
    private var lastSpeechTime: TimeInterval = 0
    var onAutoStop: (() -> Void)?

    var silenceThreshold: Double = 0.01
    var silenceTimeout: Double = 10.0

    var isRecording: Bool { engine.isRunning }

    func start() throws {
        buffer.removeAll()
        speechDetected = false
        lastSpeechTime = Date.timeIntervalSinceReferenceDate

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0 else {
            throw RecorderError.noInputDevice
        }

        // Install tap in hardware format, convert to 16kHz mono ourselves
        let tapFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hardwareFormat.sampleRate,
            channels: 1,
            interleaved: false
        )!

        let converter: AVAudioConverter?
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        )!
        if hardwareFormat.sampleRate != Self.sampleRate {
            converter = AVAudioConverter(from: tapFormat, to: targetFormat)
        } else {
            converter = nil
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] pcmBuffer, _ in
            self?.processTapBuffer(pcmBuffer, converter: converter, targetFormat: targetFormat)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        bufferLock.lock()
        let result = buffer
        bufferLock.unlock()
        return result
    }

    /// Record 2 seconds of ambient noise and return RMS.
    func calibrate(completion: @escaping (Double) -> Void) {
        var samples: [Float] = []
        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0 else {
            completion(0.01)
            return
        }

        let tapFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hardwareFormat.sampleRate,
            channels: 1,
            interleaved: false
        )!

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { pcmBuffer, _ in
            guard let data = pcmBuffer.floatChannelData?[0] else { return }
            let count = Int(pcmBuffer.frameLength)
            samples.append(contentsOf: UnsafeBufferPointer(start: data, count: count))
        }
        engine.prepare()
        try? engine.start()

        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.engine.inputNode.removeTap(onBus: 0)
            self?.engine.stop()
            let rms = Self.computeRMS(samples)
            completion(rms)
        }
    }

    // MARK: - Private

    private func processTapBuffer(_ pcmBuffer: AVAudioPCMBuffer,
                                   converter: AVAudioConverter?,
                                   targetFormat: AVAudioFormat) {
        let samples: [Float]

        if let converter = converter {
            // Resample to 16kHz
            let ratio = Self.sampleRate / pcmBuffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(pcmBuffer.frameLength) * ratio) + 1
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var error: NSError?
            converter.convert(to: outBuf, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return pcmBuffer
            }
            guard error == nil, let data = outBuf.floatChannelData?[0] else { return }
            samples = Array(UnsafeBufferPointer(start: data, count: Int(outBuf.frameLength)))
        } else {
            guard let data = pcmBuffer.floatChannelData?[0] else { return }
            samples = Array(UnsafeBufferPointer(start: data, count: Int(pcmBuffer.frameLength)))
        }

        // RMS silence detection
        let rms = Self.computeRMS(samples)
        let now = Date.timeIntervalSinceReferenceDate

        if rms > silenceThreshold {
            lastSpeechTime = now
            speechDetected = true
        } else if speechDetected && silenceTimeout > 0 {
            let silence = now - lastSpeechTime
            if silence >= silenceTimeout {
                onAutoStop?()
            }
        }

        bufferLock.lock()
        buffer.append(contentsOf: samples)
        bufferLock.unlock()
    }

    static func computeRMS(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var meanSquare: Float = 0
        vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(samples.count))
        return Double(sqrtf(meanSquare))
    }

    enum RecorderError: LocalizedError {
        case noInputDevice
        var errorDescription: String? { "No audio input device found" }
    }
}
