import Foundation

/// Encodes mono Float32 samples to a 16 kHz, 16-bit PCM WAV file — the format
/// whisper.cpp expects.
enum WavWriter {
    static func write(samples: [Float], sampleRate: Int = 16000, to url: URL) throws {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)

        // Convert Float [-1,1] -> Int16 little-endian.
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            let clamped = max(-1.0, min(1.0, s))
            let v = Int16(clamped * 32767.0)
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }

        let dataSize = UInt32(pcm.count)
        let chunkSize = 36 + dataSize

        var out = Data()
        func appendString(_ s: String) { out.append(s.data(using: .ascii)!) }
        func appendLE<T: FixedWidthInteger>(_ v: T) {
            withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) }
        }

        appendString("RIFF")
        appendLE(chunkSize)
        appendString("WAVE")
        appendString("fmt ")
        appendLE(UInt32(16))                 // fmt chunk size
        appendLE(UInt16(1))                  // PCM
        appendLE(numChannels)
        appendLE(UInt32(sampleRate))
        appendLE(byteRate)
        appendLE(blockAlign)
        appendLE(bitsPerSample)
        appendString("data")
        appendLE(dataSize)
        out.append(pcm)

        try out.write(to: url)
    }
}
