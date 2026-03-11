import SwiftUI

struct ChatInputBar: View {
  @Binding var text: String
  let isSending: Bool
  let isVoiceModeActive: Bool
  let isModelSpeaking: Bool
  let voiceConnectionState: GeminiConnectionState
  var isInputFocused: FocusState<Bool>.Binding
  let onSend: () -> Void
  let onVoiceTapped: () -> Void
  let onVoiceStop: () -> Void

  var body: some View {
    if isVoiceModeActive {
      voiceBar
    } else {
      textBar
    }
  }

  private var textBar: some View {
    HStack(spacing: 12) {
      Button(action: onVoiceTapped) {
        Image(systemName: "waveform.circle.fill")
          .font(.title)
          .foregroundStyle(Color("appPrimaryColor"))
      }
      .accessibilityLabel("Start voice mode")

      TextField("Message...", text: $text, axis: .vertical)
        .font(.body)
        .textFieldStyle(.plain)
        .focused(isInputFocused)
        .lineLimit(1...5)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 20))

      Button(action: onSend) {
        Image(systemName: "arrow.up.circle.fill")
          .font(.title)
          .foregroundStyle(canSend ? Color("appPrimaryColor") : Color(.tertiaryLabel))
      }
      .disabled(!canSend)
      .accessibilityLabel("Send message")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(.background)
  }

  private var voiceBar: some View {
    HStack(spacing: 16) {
      // Status indicator
      HStack(spacing: 8) {
        Circle()
          .fill(voiceStatusColor)
          .frame(width: 8, height: 8)

        Text(voiceStatusText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer()

      // Listening animation
      if voiceConnectionState == .ready {
        VoiceWaveform(isAnimating: isModelSpeaking)
      }

      Spacer()

      // Stop button
      Button(action: onVoiceStop) {
        Image(systemName: "stop.circle.fill")
          .font(.system(size: 36))
          .foregroundStyle(.red)
      }
      .accessibilityLabel("End voice mode")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.background)
  }

  private var canSend: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
  }

  private var voiceStatusColor: Color {
    switch voiceConnectionState {
    case .ready: return .green
    case .connecting, .settingUp: return .yellow
    case .error: return .red
    case .disconnected: return .gray
    }
  }

  private var voiceStatusText: String {
    switch voiceConnectionState {
    case .ready: return isModelSpeaking ? "Speaking" : "Listening"
    case .connecting, .settingUp: return "Connecting..."
    case .error: return "Error"
    case .disconnected: return "Disconnected"
    }
  }
}

// MARK: - Voice Waveform

struct VoiceWaveform: View {
  let isAnimating: Bool
  @State private var phase: CGFloat = 0

  var body: some View {
    HStack(spacing: 3) {
      ForEach(0..<5, id: \.self) { i in
        RoundedRectangle(cornerRadius: 1.5)
          .fill(Color("appPrimaryColor"))
          .frame(width: 3, height: barHeight(index: i))
      }
    }
    .frame(height: 20)
    .onAppear { startAnimation() }
    .onChange(of: isAnimating) { _ in startAnimation() }
  }

  private func barHeight(index: Int) -> CGFloat {
    if !isAnimating { return 6 }
    let offset = CGFloat(index) * 0.4
    return 6 + 14 * abs(sin(phase + offset))
  }

  private func startAnimation() {
    guard isAnimating else {
      withAnimation(.easeOut(duration: 0.3)) { phase = 0 }
      return
    }
    withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
      phase = .pi * 2
    }
  }
}
