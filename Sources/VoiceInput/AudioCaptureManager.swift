import AVFoundation
import Foundation
import Observation
import Speech

@Observable
final class AudioCaptureManager {
    var rmsLevel: Float = 0
    var isRunning: Bool = false

    private let engine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private let analysisQueue = DispatchQueue(label: "com.voiceinput.audio", qos: .userInteractive)

    func setRecognitionRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        recognitionRequest = request
    }

    func start() throws {
        guard !engine.isRunning else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let rms = Self.computeRMS(buffer)
            DispatchQueue.main.async {
                self.rmsLevel = rms
            }
            self.recognitionRequest?.append(buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard engine.isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        DispatchQueue.main.async {
            self.rmsLevel = 0
        }
    }

    static func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        let samples = UnsafeBufferPointer(start: channelData[0], count: frameLength)
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return sqrt(sum / Float(frameLength))
    }
}
