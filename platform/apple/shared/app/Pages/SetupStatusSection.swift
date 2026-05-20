import GUIForCLICore
import SwiftUI

struct SetupStatusSection: View {
  @Environment(\.layoutDirection) private var layoutDirection
  let steps: [SetupStep]
  let labels: BundleLocalizationLabels
  let setupRun: BundleSetupRunState?
  let isRunning: Bool
  let runningStepID: String?
  var runSetup: () -> Void
  var openBundleWorkspace: () -> Void

  private var resultsByID: [String: BundleSetupStepRunState] {
    Dictionary(uniqueKeysWithValues: (setupRun?.results ?? []).map { ($0.id, $0) })
  }

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            Text(summary)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            if let toolSummary = setupHeaderToolSummary {
              Text(toolSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          Spacer()
          Button {
            openBundleWorkspace()
          } label: {
            Label(labels.openBundleWorkspaceTitle, systemImage: "folder")
          }
          .help(labels.openBundleWorkspaceTooltip)
          if !steps.isEmpty {
            Button {
              runSetup()
            } label: {
              Label {
                Text(setupButtonTitle)
              } icon: {
                Image(systemName: "play.fill")
                  .scaleEffect(x: layoutDirection == .rightToLeft ? -1 : 1, y: 1)
              }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning)
          }
        }

        if !steps.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(steps) { step in
              setupStepRow(step)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Label(labels.setupTitle, systemImage: "gearshape.2")
    }
  }

  private var summary: String {
    guard !steps.isEmpty else { return labels.setupNoStepsTitle }
    if isRunning { return labels.setupRunningTitle }
    switch setupRun?.status {
    case "ok":
      return labels.setupStatusOkTitle
    case "failed":
      return labels.setupStatusFailedTitle
    default:
      return labels.setupStatusReadyTitle
    }
  }

  private var setupButtonTitle: String {
    if isRunning { return labels.setupRunningTitle }
    return setupRun?.status == "ok" ? labels.setupRerunButtonTitle : labels.setupRunButtonTitle
  }

  private var setupHeaderToolSummary: String? {
    let summaries = steps.compactMap { $0.setupToolSummary(labels: labels) }
    var seen = Set<String>()
    let uniqueSummaries = summaries.filter { seen.insert($0).inserted }
    return uniqueSummaries.isEmpty ? nil : uniqueSummaries.joined(separator: "; ")
  }

  private func setupStepRow(_ step: SetupStep) -> some View {
    let status = runningStepID == step.id ? "running" : resultsByID[step.id]?.status ?? "pending"
    return HStack(spacing: 10) {
      setupStatusGlyph(status)
        .frame(width: 20, height: 20)
      VStack(alignment: .leading, spacing: 2) {
        Text(step.label)
          .font(.subheadline.weight(.semibold))
      }
      Spacer()
      Text(step.kind.rawValue)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(statusLabel(status))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
  }

  @ViewBuilder private func setupStatusGlyph(_ status: String) -> some View {
    switch status {
    case "running":
      ProgressView()
        .controlSize(.small)
    case "ok":
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case "warning":
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    case "failed":
      Image(systemName: "xmark.circle.fill")
        .foregroundStyle(.red)
    default:
      Image(systemName: "circle")
        .foregroundStyle(.secondary)
    }
  }

  private func statusLabel(_ status: String) -> String {
    switch status {
    case "running":
      labels.setupStepRunningTitle
    case "ok":
      labels.setupStepOkTitle
    case "warning":
      labels.setupStepWarningTitle
    case "failed":
      labels.setupStepFailedTitle
    default:
      labels.setupStepPendingTitle
    }
  }
}

extension SetupStep {
  func setupToolSummary(labels: BundleLocalizationLabels) -> String? {
    let name = toolName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let version = toolVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
    switch (name?.isEmpty == false ? name : nil, version?.isEmpty == false ? version : nil) {
    case let (name?, version?):
      return "\(labels.setupToolLabel): \(name) \(version)"
    case let (name?, nil):
      return "\(labels.setupToolLabel): \(name)"
    case let (nil, version?):
      return "\(labels.setupVersionLabel): \(version)"
    default:
      return nil
    }
  }
}
