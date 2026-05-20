import SwiftUI

struct PlatformDebugBadge: View {
  let diameter: CGFloat
  let systemImageName: String

  var body: some View {
    ZStack {
      Circle()
        .fill(.regularMaterial)
      Circle()
        .strokeBorder(.white.opacity(0.85), lineWidth: diameter * 0.08)
      Image(systemName: systemImageName)
        .font(.system(size: diameter * 0.5, weight: .semibold))
        .foregroundStyle(.primary)
    }
    .frame(width: diameter, height: diameter)
    .shadow(color: .black.opacity(0.18), radius: diameter * 0.14, y: diameter * 0.06)
    .accessibilityHidden(true)
  }
}
