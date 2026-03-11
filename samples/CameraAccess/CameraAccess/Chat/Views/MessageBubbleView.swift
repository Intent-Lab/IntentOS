import SwiftUI

struct MessageBubbleView: View {
  let message: ChatMessage

  var body: some View {
    HStack {
      if message.role == .user { Spacer(minLength: 60) }

      VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
        if message.role == .toolCall {
          toolCallBubble
        } else if message.isAgentResult {
          agentResultCard
        } else {
          textBubble
        }
      }

      if message.role == .assistant || message.isAgentResult { Spacer(minLength: 60) }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, message.role == .toolCall ? 1 : 2)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityDescription)
  }

  // MARK: - Regular text bubble (voice transcripts, user messages)

  private var textBubble: some View {
    HStack(alignment: .bottom, spacing: 4) {
      if message.text.isEmpty && message.status == .streaming {
        Text(" ")
          .font(.body)
          .foregroundStyle(message.role == .user ? .white : .primary)
      } else {
        MarkdownTextView(
          text: message.text,
          foregroundColor: message.role == .user ? .white : .primary
        )
      }

      if message.status == .streaming {
        TypingCursor()
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 18))
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
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    .frame(maxWidth: .infinity, alignment: .center)
  }

  // MARK: - Agent result card (distinct from voice transcripts)

  private var agentResultCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack(spacing: 8) {
        Image(systemName: "cpu")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Text("Agent")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)

        Spacer()

        if message.status == .streaming {
          ProgressView()
            .controlSize(.small)
            .tint(.secondary)
        }
      }
      .padding(.horizontal, 14)
      .padding(.top, 10)
      .padding(.bottom, 8)

      // Steps (collapsed inside card)
      if !message.agentSteps.isEmpty {
        VStack(alignment: .leading, spacing: 3) {
          ForEach(message.agentSteps) { step in
            HStack(spacing: 6) {
              if step.isDone {
                if step.success {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption2)
                } else {
                  Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption2)
                }
              } else {
                ProgressView()
                  .controlSize(.mini)
                  .tint(.secondary)
              }
              Text(step.displayText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
          }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
      }

      // Divider between steps and result
      if !message.text.isEmpty {
        Rectangle()
          .fill(.separator)
          .frame(height: 0.5)
          .padding(.horizontal, 14)

        // Result content
        HStack(alignment: .bottom, spacing: 4) {
          MarkdownTextView(
            text: message.text,
            foregroundColor: .primary
          )
          if message.status == .streaming {
            TypingCursor()
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
      }
    }
    .background(
      RoundedRectangle(cornerRadius: 14)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14)
        .stroke(.separator, lineWidth: 0.5)
    )
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
