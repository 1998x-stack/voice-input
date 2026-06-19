import SwiftUI

struct CapsuleContentView: View {
    let rmsLevel: Float
    let transcription: String
    let isRefining: Bool

    var body: some View {
        HStack(spacing: 16) {
            WaveformView(rmsLevel: rmsLevel)
                .frame(width: 44, height: 32)

            if isRefining {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .controlSize(.small)
                    Text("Refining...")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.system(size: 15))
                }
                .frame(minWidth: 160, maxWidth: 560, alignment: .leading)
            } else {
                Text(transcription.isEmpty ? " " : transcription)
                    .foregroundColor(.white)
                    .font(.system(size: 15))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 160, maxWidth: 560, alignment: .leading)
                    .animation(.easeInOut(duration: 0.25), value: transcription)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
    }
}

struct WaveformView: View {
    let rmsLevel: Float

    private let weights: [Float] = [0.5, 0.8, 1.0, 0.75, 0.55]
    @State private var envelope: Float = 0
    @State private var jitters: [Float] = [0, 0, 0, 0, 0]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { _ in
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0, green: 0.478, blue: 1.0),
                                         Color(red: 0.35, green: 0.78, blue: 0.98)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 3.5, height: barHeight(for: i))
                }
            }
            .frame(width: 44, height: 32)
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let attack: Float = 0.40
        let release: Float = 0.15
        let coefficient = rmsLevel > envelope ? attack : release
        envelope = envelope * (1 - coefficient) + rmsLevel * coefficient

        jitters[index] = Float.random(in: -0.04...0.04)

        let weighted = envelope * weights[index] * (1 + jitters[index])
        let clamped = max(3, min(weighted * 32, 32))
        return CGFloat(clamped)
    }
}
