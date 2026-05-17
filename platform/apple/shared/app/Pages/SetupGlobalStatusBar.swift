import GUIForCLICore
import SwiftUI

struct SetupGlobalStatusBar: View {
  let labels: BundleLocalizationLabels
  let setupRun: BundleSetupRunState?
  let isRunning: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: isRunning ? "clock.arrow.circlepath" : "exclamationmark.triangle.fill")
          .foregroundStyle(isRunning ? Color.secondary : Color.orange)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.headline)
          Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        Spacer(minLength: 12)
        Text(isRunning ? labels.setupRunningTitle : labels.setupRunButtonTitle)
          .font(.callout.weight(.semibold))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(.regularMaterial)
    .overlay(alignment: .bottom) {
      Divider()
    }
    .accessibilityLabel("\(title). \(message)")
  }

  private var title: String { labels.setupTitle }

  private var message: String {
    switch setupRun?.status {
    case "running":
      labels.setupRunningTitle
    case "failed":
      labels.setupStatusFailedTitle
    default:
      labels.setupStatusReadyTitle
    }
  }
}
