import SwiftUI

struct ChatTopBar: View {
  let showGlassesButton: Bool
  let onGlassesTapped: () -> Void
  let onGalleryTapped: () -> Void
  let onSettingsTapped: () -> Void

  var body: some View {
    HStack {
      // Title as glass pill (left)
      Text("Matcha")
        .font(AppFont.headline)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 0.5))

      Spacer()

      // Right-side action buttons as glass pills
      HStack(spacing: 6) {
        if showGlassesButton {
          glassButton(icon: "eyeglasses", label: "Open glasses streaming", action: onGlassesTapped)
        }

        glassButton(icon: "photo.on.rectangle", label: "Photo gallery", action: onGalleryTapped)

        glassButton(icon: "gearshape", label: "Settings", action: onSettingsTapped)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }

  private func glassButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(.primary)
        .frame(width: 36, height: 36)
        .background(.ultraThinMaterial, in: Circle())
        .overlay(Circle().strokeBorder(.quaternary, lineWidth: 0.5))
    }
    .accessibilityLabel(label)
  }
}
