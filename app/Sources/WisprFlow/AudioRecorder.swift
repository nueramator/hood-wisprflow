import AVFoundation

/// Captures microphone audio and resamples it to 16 kHz mono Float32 while
/// recording. `stop()` returns the accumulated samples.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat!
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var isRecording = false

    /// Smoothed 0…1 loudness, delivered on the main thread for the HUD meter.
    var onLevel: ((Float) -> Void)?
    private var smoothedLevel: Float = 0

    /// Requests mic access (prompts once). Completion on an arbitrary queue.
    func requestPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { completion($0) }
        default: completion(false)
        }
    }

    func start() throws {
        guard !isRecording else { return }
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                     sampleRate: 16000, channels: 1, interleaved: false)!
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.ingest(buffer)
        }
        engine.prepare()
        try engine.start()
        isRecording = true
    }

    /// Stops capture and returns the recorded samples (16 kHz mono).
    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        lock.lock(); let out = samples; lock.unlock()
        return out
    }

    private func ingest(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat else { return }

        // Estimate output capacity from the sample-rate ratio.
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, let channel = outBuffer.floatChannelData?[0] else { return }
        let count = Int(outBuffer.frameLength)
        let slice = Array(UnsafeBufferPointer(start: channel, count: count))
        lock.lock(); samples.append(contentsOf: slice); lock.unlock()

        // RMS → perceptual 0…1 level for the meter, with attack/decay smoothing.
        if let onLevel, count > 0 {
            var sum: Float = 0
            for s in slice { sum += s * s }
            let rms = (sum / Float(count)).squareRoot()
            let scaled = min(1.0, rms * 12.0).squareRoot()   // lift quiet speech
            let coeff: Float = scaled > smoothedLevel ? 0.5 : 0.15   // fast attack, slow release
            smoothedLevel += (scaled - smoothedLevel) * coeff
            let out = smoothedLevel
            DispatchQueue.main.async { onLevel(out) }
        }
    }
}
