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
        .modifier(LiquidGlassModifier(shape: .capsule))

      Spacer()

      // Right-side action buttons as glass circles
      GlassButtonGroup {
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
        .modifier(LiquidGlassModifier(shape: .circle, interactive: true))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }
}

// MARK: - Liquid Glass Helpers

enum GlassShape {
  case capsule
  case circle
}

/// Applies iOS 26 Liquid Glass when available, falls back to ultraThinMaterial
struct LiquidGlassModifier: ViewModifier {
  let shape: GlassShape
  var interactive: Bool = false

  func body(content: Content) -> some View {
    if #available(iOS 26, *) {
      let glass: Glass = interactive ? .regular.interactive() : .regular
      switch shape {
      case .capsule:
        content.glassEffect(glass, in: .capsule)
      case .circle:
        content.glassEffect(glass, in: .circle)
      }
    } else {
      switch shape {
      case .capsule:
        content
          .background(.ultraThinMaterial, in: Capsule())
          .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 0.5))
      case .circle:
        content
          .background(.ultraThinMaterial, in: Circle())
          .overlay(Circle().strokeBorder(.quaternary, lineWidth: 0.5))
      }
    }
  }
}

/// Wraps children in GlassEffectContainer on iOS 26+
struct GlassButtonGroup<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    if #available(iOS 26, *) {
      GlassEffectContainer {
        HStack(spacing: 6) {
          content
        }
      }
    } else {
      HStack(spacing: 6) {
        content
      }
    }
  }
}
