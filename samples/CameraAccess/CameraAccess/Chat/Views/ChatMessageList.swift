import SwiftUI

struct ChatMessageList: View {
  let messages: [ChatMessage]

  @State private var userScrolledUp = false

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

            // Invisible anchor at the bottom to detect scroll position
            Color.clear
              .frame(height: 1)
              .id("bottom")
              .onAppear { userScrolledUp = false }
              .onDisappear { userScrolledUp = true }
          }
          .padding(.vertical, 12)
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: messages.count) { _ in
        scrollToBottomIfAllowed(proxy: proxy)
      }
      .onChange(of: messages.last?.text) { _ in
        scrollToBottomIfAllowed(proxy: proxy)
      }
    }
  }

  private func scrollToBottomIfAllowed(proxy: ScrollViewProxy) {
    guard !userScrolledUp, let lastId = messages.last?.id else { return }
    withAnimation(.easeOut(duration: 0.15)) {
      proxy.scrollTo(lastId, anchor: .bottom)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Spacer()
      Image(systemName: "bubble.left.and.bubble.right")
        .font(.system(size: 48))
        .foregroundStyle(.tertiary)
      Text("How can I help?")
        .font(AppFont.title3)
        .foregroundStyle(.secondary)
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.top, 120)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Chat is empty. Type a message or start voice mode.")
  }
}
