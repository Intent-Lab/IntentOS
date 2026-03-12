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

  // MARK: - Text Input (Floating Glass Bubble)

  private var textBar: some View {
    HStack(spacing: 10) {
      // Voice mode button
      Button(action: onVoiceTapped) {
        Image(systemName: "waveform")
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(.secondary)
          .frame(width: 32, height: 32)
      }
      .accessibilityLabel("Start voice mode")

      // Text field
      TextField("Message...", text: $text, axis: .vertical)
        .font(AppFont.body)
        .textFieldStyle(.plain)
        .focused(isInputFocused)
        .lineLimit(1...5)

      // Send button (only when there's text)
      if canSend {
        Button(action: onSend) {
          Image(systemName: "arrow.up")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Color("appPrimaryColor"), in: Circle())
        }
        .accessibilityLabel("Send message")
        .transition(.scale.combined(with: .opacity))
      }
    }
    .padding(.leading, 8)
    .padding(.trailing, canSend ? 8 : 12)
    .padding(.vertical, 8)
    .modifier(LiquidGlassModifier(shape: .capsule))
    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    .padding(.horizontal, 16)
    .padding(.bottom, 8)
    .animation(.easeInOut(duration: 0.2), value: canSend)
  }

  // MARK: - Voice Mode (Floating Glass Bubble)

  private var voiceBar: some View {
    HStack(spacing: 12) {
      // Status indicator
      HStack(spacing: 8) {
        Circle()
          .fill(voiceStatusColor)
          .frame(width: 8, height: 8)

        Text(voiceStatusText)
          .font(AppFont.subheadline)
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
        Image(systemName: "stop.fill")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 32, height: 32)
          .background(.red, in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("End voice mode")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .modifier(LiquidGlassModifier(shape: .capsule))
    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    .padding(.horizontal, 16)
    .padding(.bottom, 8)
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
    case .connecting, .settingUp: return "Reconnecting..."
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
