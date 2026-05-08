import GUIForCLICore
import SwiftUI

@MainActor
final class AppTextScale: ObservableObject {
  private static let defaultsKey = "appTextScaleStep"
  private static let minimumStep = -3
  private static let maximumStep = 5

  @Published private(set) var step: Int {
    didSet {
      UserDefaults.standard.set(step, forKey: Self.defaultsKey)
    }
  }

  init() {
    step = UserDefaults.standard.integer(forKey: Self.defaultsKey)
    step = Self.clamped(step)
  }

  var dynamicTypeSize: DynamicTypeSize {
    switch step {
    case ...(-3):
      return .xSmall
    case -2:
      return .small
    case -1:
      return .medium
    case 0:
      return .large
    case 1:
      return .xLarge
    case 2:
      return .xxLarge
    case 3:
      return .xxxLarge
    case 4:
      return .accessibility1
    default:
      return .accessibility2
    }
  }

  var canIncrease: Bool { step < Self.maximumStep }
  var canDecrease: Bool { step > Self.minimumStep }
  var canReset: Bool { step != 0 }

  func increase() {
    step = Self.clamped(step + 1)
  }

  func decrease() {
    step = Self.clamped(step - 1)
  }

  func reset() {
    step = 0
  }

  private static func clamped(_ step: Int) -> Int {
    min(max(step, minimumStep), maximumStep)
  }
}
