import SwiftUI

struct VoiceModeOverlay: View {
  @ObservedObject var viewModel: ChatViewModel

  var body: some View {
    ZStack {
      Color.black.opacity(0.9)
        .ignoresSafeArea()

      VStack(spacing: 24) {
        HStack(spacing: 8) {
          StatusPill(color: geminiStatusColor, text: geminiStatusText)
        }
        .padding(.top, 16)

        Spacer()

        VoiceOrb(isSpeaking: viewModel.isModelSpeaking)

        VStack(spacing: 8) {
          if !viewModel.userTranscript.isEmpty {
            Text(viewModel.userTranscript)
              .font(AppFont.subheadline)
              .foregroundStyle(.white.opacity(0.7))
              .multilineTextAlignment(.center)
          }
          if !viewModel.aiTranscript.isEmpty {
            Text(viewModel.aiTranscript)
              .font(AppFont.bodyMedium)
              .foregroundStyle(.white)
              .multilineTextAlignment(.center)
          }
        }
        .padding(.horizontal, 32)
        .frame(minHeight: 60)
        .accessibilityElement(children: .combine)

        ToolCallStatusView(status: viewModel.toolCallStatus)

        Spacer()

        Button {
          viewModel.stopVoiceMode()
        } label: {
          Image(systemName: "xmark")
            .font(.title3.bold())
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(.red, in: Circle())
        }
        .accessibilityLabel("End voice mode")
        .padding(.bottom, 40)
      }
    }
    .transition(.opacity)
  }
}

// MARK: - Voice Visualization

struct VoiceOrb: View {
  let isSpeaking: Bool
  @State private var scale: CGFloat = 1.0
  @State private var innerScale: CGFloat = 1.0

  var body: some View {
    ZStack {
      Circle()
        .stroke(.white.opacity(0.15), lineWidth: 2)
        .frame(width: 140, height: 140)
        .scaleEffect(scale)

      Circle()
        .stroke(.white.opacity(0.25), lineWidth: 2)
        .frame(width: 110, height: 110)
        .scaleEffect(innerScale)

      Circle()
        .fill(.white.opacity(isSpeaking ? 0.3 : 0.15))
        .frame(width: 80, height: 80)

      if isSpeaking {
        SpeakingIndicator()
      } else {
        Image(systemName: "waveform")
          .font(.title2)
          .foregroundStyle(.white.opacity(0.5))
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(isSpeaking ? "AI is speaking" : "Listening")
    .onChange(of: isSpeaking) { speaking in
      withAnimation(speaking ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .easeOut(duration: 0.3)) {
        scale = speaking ? 1.15 : 1.0
        innerScale = speaking ? 1.1 : 1.0
      }
    }
  }
}

// MARK: - Status helpers

private extension VoiceModeOverlay {
  var geminiStatusColor: Color {
    switch viewModel.voiceConnectionState {
    case .ready: return .green
    case .connecting, .settingUp: return .yellow
    case .error: return .red
    case .disconnected: return .gray
    }
  }

  var geminiStatusText: String {
    switch viewModel.voiceConnectionState {
    case .ready: return "Voice Active"
    case .connecting, .settingUp: return "Connecting..."
    case .error: return "Error"
    case .disconnected: return "Disconnected"
    }
  }
}
