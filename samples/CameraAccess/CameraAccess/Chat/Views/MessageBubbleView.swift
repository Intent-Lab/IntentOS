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
  }

  private var textBubble: some View {
    HStack(alignment: .bottom, spacing: 4) {
      Text(message.text.isEmpty && message.status == .streaming ? " " : message.text)
        .font(.system(size: 16))
        .foregroundColor(message.role == .user ? .white : .primary)

      if message.status == .streaming {
        TypingCursor()
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(bubbleBackground)
    .cornerRadius(18)
  }

  private var toolCallBubble: some View {
    HStack(spacing: 8) {
      if message.status == .streaming {
        ProgressView()
          .scaleEffect(0.7)
          .tint(.secondary)
      } else if case .error = message.status {
        Image(systemName: "exclamationmark.circle.fill")
          .foregroundColor(.red)
          .font(.system(size: 13))
      } else {
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.green)
          .font(.system(size: 13))
      }
      Text(message.text)
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(.secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Color(.systemGray5))
    .cornerRadius(12)
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private var bubbleBackground: Color {
    switch message.role {
    case .user: return Color("appPrimaryColor")
    case .assistant: return Color(.systemGray6)
    case .toolCall: return Color(.systemGray5)
    }
  }
}

struct TypingCursor: View {
  @State private var visible = true

  var body: some View {
    Rectangle()
      .fill(Color.secondary)
      .frame(width: 2, height: 16)
      .opacity(visible ? 1 : 0)
      .onAppear {
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
          visible = false
        }
      }
  }
}
