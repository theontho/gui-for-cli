import GUIForCLICore
import SwiftUI

struct ControlRenderer: View {
  @EnvironmentObject var terminal: TerminalLogStore
  @EnvironmentObject var configStore: BundleConfigStore
  let control: ControlSpec
  let localizationLabels: BundleLocalizationLabels
  @Binding var value: String
  @Binding var checkedIDs: Set<String>
  let bundleRootURL: URL?
  var runAction: (ActionSpec, CommandRenderContext) -> Void
  @State var dynamicData = DynamicControlData()
  @State var dataSourceError: String?
  @State var isRefreshingDataSource = false

  var body: some View {
    let renderedControl = control.applying(dynamicData)
    subview(for: renderedControl)
      .overlay(alignment: .bottomLeading) {
        if let dataSourceError, renderedControl.kind != .libraryList {
          Text(dataSourceError)
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.top, 4)
        }
      }
      .task(id: dataSourceTaskID) {
        await loadDataSourceIfNeeded(clearExistingData: true)
      }
      .onChange(of: terminal.commandCompletionSerial) {
        refreshDataSourceAfterControlActionIfNeeded()
      }
  }
}
