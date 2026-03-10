import SwiftUI

struct VoiceModeOverlay: View {
  @ObservedObject var viewModel: ChatViewModel

  var body: some View {
    ZStack {
      Color.black.opacity(0.9)
        .ignoresSafeArea()

      VStack(spacing: 24) {
        // Status pills
        HStack(spacing: 8) {
          StatusPill(color: geminiStatusColor, text: geminiStatusText)
        }
        .padding(.top, 16)

        Spacer()

        // Voice visualization
        VoiceOrb(isSpeaking: viewModel.isModelSpeaking)

        // Transcripts
        VStack(spacing: 8) {
          if !viewModel.userTranscript.isEmpty {
            Text(viewModel.userTranscript)
              .font(.system(size: 15))
              .foregroundColor(.white.opacity(0.7))
              .multilineTextAlignment(.center)
          }
          if !viewModel.aiTranscript.isEmpty {
            Text(viewModel.aiTranscript)
              .font(.system(size: 17, weight: .medium))
              .foregroundColor(.white)
              .multilineTextAlignment(.center)
          }
        }
        .padding(.horizontal, 32)
        .frame(minHeight: 60)

        // Tool call status
        ToolCallStatusView(status: viewModel.toolCallStatus)

        Spacer()

        // End button
        Button {
          viewModel.stopVoiceMode()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 64, height: 64)
            .background(Color.red)
            .clipShape(Circle())
        }
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
      // Outer ring
      Circle()
        .stroke(Color.white.opacity(0.15), lineWidth: 2)
        .frame(width: 140, height: 140)
        .scaleEffect(scale)

      // Middle ring
      Circle()
        .stroke(Color.white.opacity(0.25), lineWidth: 2)
        .frame(width: 110, height: 110)
        .scaleEffect(innerScale)

      // Center orb
      Circle()
        .fill(Color.white.opacity(isSpeaking ? 0.3 : 0.15))
        .frame(width: 80, height: 80)

      // Speaking bars (centered in orb)
      if isSpeaking {
        SpeakingIndicator()
      } else {
        Image(systemName: "waveform")
          .font(.system(size: 24))
          .foregroundColor(.white.opacity(0.5))
      }
    }
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
