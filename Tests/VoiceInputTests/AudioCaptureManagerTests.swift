import XCTest
import AVFoundation
@testable import VoiceInput

final class AudioCaptureManagerTests: XCTestCase {

    func testComputeRMS_silence() {
        let buffer = makeFloatBuffer(samples: [Float](repeating: 0, count: 1024))
        let rms = AudioCaptureManager.computeRMS(buffer)
        XCTAssertEqual(rms, 0, accuracy: 0.0001)
    }

    func testComputeRMS_uniformSignal() {
        let buffer = makeFloatBuffer(samples: [Float](repeating: 0.5, count: 512))
        let rms = AudioCaptureManager.computeRMS(buffer)
        XCTAssertEqual(rms, 0.5, accuracy: 0.0001)
    }

    func testComputeRMS_maxAmplitude() {
        let buffer = makeFloatBuffer(samples: [Float](repeating: 1.0, count: 256))
        let rms = AudioCaptureManager.computeRMS(buffer)
        XCTAssertEqual(rms, 1.0, accuracy: 0.0001)
    }

    func testComputeRMS_alternatingSignal() {
        // Alternating +0.6, -0.6 → RMS = 0.6
        var samples: [Float] = []
        for i in 0..<1024 {
            samples.append(i % 2 == 0 ? 0.6 : -0.6)
        }
        let buffer = makeFloatBuffer(samples: samples)
        let rms = AudioCaptureManager.computeRMS(buffer)
        XCTAssertEqual(rms, 0.6, accuracy: 0.0001)
    }

    func testComputeRMS_emptyBuffer() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
            XCTFail("Could not create audio format")
            return
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 0) else {
            XCTFail("Could not create buffer")
            return
        }
        buffer.frameLength = 0
        let rms = AudioCaptureManager.computeRMS(buffer)
        XCTAssertEqual(rms, 0, accuracy: 0.0001)
    }

    // MARK: - Helpers

    private func makeFloatBuffer(samples: [Float]) -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
            fatalError("Could not create audio format")
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            fatalError("Could not create buffer")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channelData = buffer.floatChannelData {
            for i in 0..<samples.count {
                channelData[0][i] = samples[i]
            }
        }
        return buffer
    }
}
