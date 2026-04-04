import SwiftUI

struct SpeechHUDView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            switch appState.speechHUDPhase {
            case .recording:
                recordingHUD
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.6).combined(with: .opacity),
                            removal: .scale(scale: 0.85).combined(with: .opacity)
                        )
                    )
            case .transcribing:
                transcribingHUD
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.6).combined(with: .opacity),
                            removal: .scale(scale: 0.85).combined(with: .opacity)
                        )
                    )
            case .hidden:
                EmptyView()
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: appState.speechHUDPhase)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Recording HUD

    private var recordingHUD: some View {
        HStack(spacing: 14) {
            RMSWaveformView(audioLevel: appState.audioLevel)
                .frame(width: 44, height: 32)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 24)

            AutoScrollingTranscriptView(text: recordingText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 16)
        .padding(.trailing, 20)
        .frame(height: 56)
        .background(
            ZStack {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
            .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 12)
            .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
        )
        .clipShape(Capsule(style: .continuous))
    }

    // MARK: - Transcribing HUD

    private var transcribingHUD: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
                .scaleEffect(0.82)

            Text("转写中")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(
            ZStack {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.3))
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.3), radius: 18, x: 0, y: 10)
        )
        .clipShape(Capsule(style: .continuous))
    }

    private var recordingText: String {
        let text = appState.transcriptPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "语音输入" : text
    }
}

// MARK: - Auto-Scrolling Transcript

private struct AutoScrollingTranscriptView: View {
    let text: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    Text(text)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
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

// MARK: - RMS Waveform (5 bars, envelope-smoothed, real audio data)

private struct RMSWaveformView: View {
    let audioLevel: Float

    private static let barCount = 5
    private static let barWeights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private static let barSpacing: CGFloat = 4
    private static let barWidth: CGFloat = 4
    private static let barCornerRadius: CGFloat = 2
    private static let minBarHeight: CGFloat = 4
    private static let maxBarHeight: CGFloat = 30

    @State private var smoothedLevel: CGFloat = 0
    @State private var barJitter: [CGFloat] = (0..<5).map { _ in CGFloat.random(in: -0.04...0.04) }
    @State private var idlePhase: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            HStack(alignment: .center, spacing: Self.barSpacing) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: Self.barCornerRadius, style: .continuous)
                        .fill(barGradient)
                        .frame(width: Self.barWidth, height: barHeight(for: index))
                }
            }
            .onChange(of: timeline.date) { _, _ in
                updateEnvelope()
                updateJitter()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                idlePhase = 1
            }
        }
    }

    private var barGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.40, green: 0.95, blue: 0.70),
                Color(red: 0.20, green: 0.78, blue: 0.55)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func barHeight(for index: Int) -> CGFloat {
        let weight = Self.barWeights[index]
        let jitter = 1.0 + barJitter[index]

        if smoothedLevel < 0.005 {
            let offsets: [CGFloat] = [0.0, 0.25, 0.5, 0.75, 0.4]
            let wave = abs(sin((idlePhase + offsets[index]) * .pi))
            let idleHeight = Self.minBarHeight + wave * 3 * weight
            return idleHeight
        }

        let driven = smoothedLevel * weight * jitter
        let height = Self.minBarHeight + driven * (Self.maxBarHeight - Self.minBarHeight)
        return min(max(height, Self.minBarHeight), Self.maxBarHeight)
    }

    private func updateEnvelope() {
        let raw = CGFloat(min(max(audioLevel, 0), 1.0))
        let normalized = min(raw / 0.25, 1.0)

        if normalized > smoothedLevel {
            smoothedLevel += (normalized - smoothedLevel) * 0.40
        } else {
            smoothedLevel += (normalized - smoothedLevel) * 0.15
        }
    }

    private func updateJitter() {
        for i in 0..<Self.barCount {
            barJitter[i] = CGFloat.random(in: -0.04...0.04)
        }
    }
}
