import SwiftUI

struct MessageBubbleView: View {
  let message: ChatMessage

  var body: some View {
    Group {
      if message.role == .toolCall {
        toolCallBubble
      } else if message.role == .user {
        HStack {
          Spacer(minLength: 60)
          textBubble
        }
      } else {
        // Assistant: plain text, no bubble, equal left/right padding
        assistantText
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, message.role == .toolCall ? 1 : 2)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityDescription)
  }

  // MARK: - User bubble (with background)

  private var textBubble: some View {
    HStack(alignment: .bottom, spacing: 4) {
      if message.text.isEmpty && message.status == .streaming {
        Text(" ")
          .font(AppFont.body)
          .foregroundStyle(.white)
      } else {
        MarkdownTextView(
          text: message.text,
          foregroundColor: .white
        )
      }

      if message.status == .streaming {
        TypingCursor()
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(Color("appPrimaryColor"), in: RoundedRectangle(cornerRadius: 18))
  }

  // MARK: - Assistant text (no bubble, plain text)

  private var assistantText: some View {
    HStack(alignment: .bottom, spacing: 4) {
      if message.text.isEmpty && message.status == .streaming {
        Text(" ")
          .font(AppFont.body)
          .foregroundStyle(.primary)
      } else {
        MarkdownTextView(
          text: message.text,
          foregroundColor: .primary
        )
      }

      if message.status == .streaming {
        TypingCursor()
      }
    }
  }

  // MARK: - Tool call step indicator (small pill)

  private var toolCallBubble: some View {
    HStack(spacing: 6) {
      if message.status == .streaming {
        ProgressView()
          .controlSize(.small)
          .tint(.secondary)
      } else if case .error = message.status {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.red)
          .font(.caption2)
      } else {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .font(.caption2)
      }
      Text(message.text)
        .font(AppFont.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    .frame(maxWidth: .infinity, alignment: .center)
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
