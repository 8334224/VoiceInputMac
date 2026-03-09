import SwiftUI

struct SpeechHUDView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            switch appState.speechHUDPhase {
            case .recording:
                recordingHUD
            case .transcribing:
                transcribingHUD
            case .hidden:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(8)
    }

    private var recordingHUD: some View {
        let capsuleShape = Capsule(style: .continuous)

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            AutoScrollingTranscriptView(text: recordingText)
                .frame(maxWidth: .infinity, alignment: .leading)

            RecordingBarsView()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.79, blue: 0.56),
                            Color(red: 0.09, green: 0.74, blue: 0.49)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 10)
        )
        .clipShape(capsuleShape)
    }

    private var transcribingHUD: some View {
        HStack(spacing: 10) {
            Text("转写中")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Rectangle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 1, height: 18)

            ProgressView()
                .controlSize(.small)
                .tint(.white)
                .scaleEffect(0.8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 10)
        )
    }

    private var recordingText: String {
        let text = appState.transcriptPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return "语音输入"
        }
        return text
    }
}

private struct AutoScrollingTranscriptView: View {
    let text: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    Text(text)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Color.clear
                        .frame(width: 1, height: 1)
                        .id("tail")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipped()
            .allowsHitTesting(false)
            .onAppear {
                proxy.scrollTo("tail", anchor: .trailing)
            }
            .onChange(of: text) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("tail", anchor: .trailing)
                }
            }
        }
        .frame(height: 22)
    }
}

private struct RecordingBarsView: View {
    @State private var phase: CGFloat = 0
    private let barCount = 4

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 4, height: barHeight(for: index))
            }
        }
        .frame(width: 28, height: 22, alignment: .center)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.68).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let offsets: [CGFloat] = [0.05, 0.42, 0.75, 1.1]
        let wave = abs(sin((phase + offsets[index]) * .pi))
        return 8 + wave * 9
    }
}
