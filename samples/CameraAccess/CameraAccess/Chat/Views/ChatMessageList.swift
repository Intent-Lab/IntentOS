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
        .foregroundColor(Color(.systemGray4))
      Text("How can I help?")
        .font(.system(size: 18, weight: .medium))
        .foregroundColor(.secondary)
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.top, 120)
  }
}
