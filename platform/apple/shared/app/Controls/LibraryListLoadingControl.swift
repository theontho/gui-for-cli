import GUIForCLICore
import SwiftUI

struct LibraryListLoadingControl: View {
  let control: ControlSpec
  let localizationLabels: BundleLocalizationLabels
  var isLoading: Bool
  var errorMessage: String?
  var retry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      InfoLabel(text: control.label, tooltip: control.tooltip, font: .headline)

      if isLoading {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text(localizationLabels.loadingTitle)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
      } else if let errorMessage {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
              .foregroundStyle(.orange)
            Text(errorMessage)
              .foregroundStyle(.secondary)
          }
          Button(localizationLabels.retryButtonTitle, action: retry)
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
      }
    }
    .help(control.tooltip ?? "")
  }
}
