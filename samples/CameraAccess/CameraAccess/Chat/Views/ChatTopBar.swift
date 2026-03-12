import SwiftUI

struct ChatTopBar: View {
  let showGlassesButton: Bool
  let onGlassesTapped: () -> Void
  let onSettingsTapped: () -> Void

  var body: some View {
    HStack {
      Text("Matcha")
        .font(AppFont.headline)

      Spacer()

      if showGlassesButton {
        Button(action: onGlassesTapped) {
          Image(systemName: "eyeglasses")
            .font(.body)
            .foregroundStyle(.primary)
        }
        .accessibilityLabel("Open glasses streaming")
        .padding(.trailing, 8)
      }

      Button(action: onSettingsTapped) {
        Image(systemName: "gearshape")
          .font(.body)
          .foregroundStyle(.primary)
      }
      .accessibilityLabel("Settings")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(.background)
  }
}
