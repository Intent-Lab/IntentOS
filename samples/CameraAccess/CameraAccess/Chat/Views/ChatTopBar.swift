import SwiftUI

struct ChatTopBar: View {
  let showGlassesButton: Bool
  let onGlassesTapped: () -> Void
  let onSettingsTapped: () -> Void

  var body: some View {
    HStack {
      Text("Matcha")
        .font(.system(size: 20, weight: .bold))

      Spacer()

      if showGlassesButton {
        Button(action: onGlassesTapped) {
          Image(systemName: "eyeglasses")
            .font(.system(size: 18))
            .foregroundColor(.primary)
        }
        .padding(.trailing, 8)
      }

      Button(action: onSettingsTapped) {
        Image(systemName: "gearshape")
          .font(.system(size: 18))
          .foregroundColor(.primary)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(Color(.systemBackground))
  }
}
