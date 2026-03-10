import SwiftUI

struct MessageBubbleView: View {
  let message: ChatMessage

  var body: some View {
    HStack {
      if message.role == .user { Spacer(minLength: 60) }

      VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
        if message.role == .toolCall {
          toolCallBubble
        } else {
          textBubble
        }
      }

      if message.role == .assistant { Spacer(minLength: 60) }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityDescription)
  }

  private var textBubble: some View {
    HStack(alignment: .bottom, spacing: 4) {
      Text(message.text.isEmpty && message.status == .streaming ? " " : message.text)
        .font(.body)
        .foregroundStyle(message.role == .user ? .white : .primary)

      if message.status == .streaming {
        TypingCursor()
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 18))
  }

  private var toolCallBubble: some View {
    HStack(spacing: 8) {
      if message.status == .streaming {
        ProgressView()
          .controlSize(.small)
          .tint(.secondary)
      } else if case .error = message.status {
        Image(systemName: "exclamationmark.circle.fill")
          .foregroundStyle(.red)
          .font(.caption)
      } else {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .font(.caption)
      }
      Text(message.text)
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private var bubbleBackground: Color {
    switch message.role {
    case .user: return Color("appPrimaryColor")
    case .assistant: return Color(.secondarySystemGroupedBackground)
    case .toolCall: return Color(.tertiarySystemFill)
    }
  }

  private var accessibilityDescription: String {
    let role = message.role == .user ? "You" : "Assistant"
    return "\(role): \(message.text)"
  }
}

struct TypingCursor: View {
  @State private var visible = true

  var body: some View {
    RoundedRectangle(cornerRadius: 1)
      .fill(.secondary)
      .frame(width: 2, height: 16)
      .opacity(visible ? 1 : 0)
      .onAppear {
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
          visible = false
        }
      }
      .accessibilityHidden(true)
  }
}
