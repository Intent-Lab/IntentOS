import SwiftUI

struct ChatMessageList: View {
  let messages: [ChatMessage]

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        if messages.isEmpty {
          emptyState
        } else {
          LazyVStack(spacing: 0) {
            ForEach(messages) { message in
              MessageBubbleView(message: message)
                .id(message.id)
            }
          }
          .padding(.vertical, 12)
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: messages.count) { _ in
        if let lastId = messages.last?.id {
          withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastId, anchor: .bottom)
          }
        }
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Spacer()
      Image(systemName: "bubble.left.and.bubble.right")
        .font(.system(size: 48))
        .foregroundStyle(.tertiary)
      Text("How can I help?")
        .font(.title3)
        .foregroundStyle(.secondary)
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.top, 120)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Chat is empty. Type a message or start voice mode.")
  }
}
