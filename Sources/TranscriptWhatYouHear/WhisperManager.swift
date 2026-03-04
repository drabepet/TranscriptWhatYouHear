import Foundation
import whisper

/// Manages whisper.cpp model loading, downloading, and transcription.
final class WhisperManager {
    private var ctx: OpaquePointer?
    private(set) var currentModel: String = ""
    private(set) var isLoading = false

    private static let modelsDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TranscriptWhatYouHear/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var onProgress: ((String) -> Void)?

    deinit {
        if let ctx = ctx { whisper_free(ctx) }
    }

    // MARK: - Model Management

    func modelPath(for size: String) -> URL {
        Self.modelsDir.appendingPathComponent("ggml-\(size).bin")
    }

    func isModelDownloaded(_ size: String) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(for: size).path)
    }

    /// Download model if needed, then load it. Calls back on main thread.
    func loadModel(_ size: String, completion: @escaping (Result<Void, Error>) -> Void) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                if !self.isModelDownloaded(size) {
                    DispatchQueue.main.async { self.onProgress?("Downloading Whisper \(size)…") }
                    try self.downloadModel(size)
                }

                DispatchQueue.main.async { self.onProgress?("Loading Whisper \(size)…") }

                if let old = self.ctx { whisper_free(old) }

                let path = self.modelPath(for: size).path
                let cparams = whisper_context_default_params()
                guard let newCtx = whisper_init_from_file_with_params(path, cparams) else {
                    throw WhisperError.loadFailed
                }
                self.ctx = newCtx
                self.currentModel = size

                Log.info("Model loaded — warming up…")
                self.warmup()
                Log.debug("Warmup complete")

                self.isLoading = false
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                self.isLoading = false
                Log.error("Model load failed: \(error)")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Transcription

    struct TranscriptionResult {
        let text: String
        let segments: [String]
        let language: String
    }

    /// Transcribe Float32 PCM samples at 16 kHz.
    func transcribe(samples: [Float], language: String,
                    streaming: Bool = false,
                    onSegment: ((String) -> Void)? = nil) -> TranscriptionResult? {
        guard let ctx = ctx else { return nil }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(min(ProcessInfo.processInfo.activeProcessorCount, 8))
        params.translate = false
        params.print_special = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.single_segment = false

        let result: Int32 = language.withCString { lang in
            params.language = lang
            return samples.withUnsafeBufferPointer { buf in
                whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
            }
        }

        guard result == 0 else {
            Log.error("whisper_full failed with code \(result)")
            return nil
        }

        // Collect all segments
        var segmentTexts: [String] = []
        let count = whisper_full_n_segments(ctx)
        for i in 0..<count {
            if let cStr = whisper_full_get_segment_text(ctx, i) {
                let text = String(cString: cStr).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    segmentTexts.append(text)
                    if streaming { onSegment?(text) }
                }
            }
        }

        let fullText = segmentTexts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return TranscriptionResult(text: fullText, segments: segmentTexts, language: language)
    }

    // MARK: - Private

    private func warmup() {
        let silentSamples = [Float](repeating: 0, count: Int(AudioRecorder.sampleRate) / 2)
        _ = transcribe(samples: silentSamples, language: "en")
    }

    private func downloadModel(_ size: String) throws {
        let urlString = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(size).bin"
        guard let url = URL(string: urlString) else { throw WhisperError.invalidURL }

        let dest = modelPath(for: size)
        Log.info("Downloading \(urlString)…")

        let semaphore = DispatchSemaphore(value: 0)
        var downloadError: Error?

        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            defer { semaphore.signal() }
            if let error = error { downloadError = error; return }
            guard let tempURL = tempURL else { downloadError = WhisperError.downloadFailed; return }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                downloadError = WhisperError.httpError(httpResponse.statusCode)
                return
            }

            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: tempURL, to: dest)
                Log.info("Model downloaded: \(dest.lastPathComponent)")
            } catch {
                downloadError = error
            }
        }
        task.resume()
        semaphore.wait()

        if let error = downloadError { throw error }
    }

    enum WhisperError: LocalizedError {
        case loadFailed
        case invalidURL
        case downloadFailed
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .loadFailed: return "Failed to load whisper model"
            case .invalidURL: return "Invalid model URL"
            case .downloadFailed: return "Model download failed"
            case .httpError(let code): return "HTTP error \(code)"
            }
        }
    }
}
