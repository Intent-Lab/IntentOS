import SwiftUI

struct ChatInputBar: View {
  @Binding var text: String
  let isSending: Bool
  let onSend: () -> Void
  let onVoiceTapped: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      // Voice mode button
      Button(action: onVoiceTapped) {
        Image(systemName: "waveform.circle.fill")
          .font(.system(size: 32))
          .foregroundColor(Color("appPrimaryColor"))
      }

      // Text field
      TextField("Message...", text: $text, axis: .vertical)
        .textFieldStyle(.plain)
        .lineLimit(1...5)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(20)

      // Send button
      Button(action: onSend) {
        Image(systemName: "arrow.up.circle.fill")
          .font(.system(size: 32))
          .foregroundColor(canSend ? Color("appPrimaryColor") : Color(.systemGray4))
      }
      .disabled(!canSend)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(Color(.systemBackground))
  }

  private var canSend: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
  }
}
