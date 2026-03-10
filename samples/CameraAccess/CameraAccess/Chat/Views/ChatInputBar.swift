import SwiftUI

struct ChatInputBar: View {
  @Binding var text: String
  let isSending: Bool
  let onSend: () -> Void
  let onVoiceTapped: () -> Void

  var body: some View {
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

  private var canSend: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
  }
}
