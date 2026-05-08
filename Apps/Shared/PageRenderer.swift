import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct PageRenderer: View {
  let page: BundlePage
  let localizationLabels: BundleLocalizationLabels
  @Binding var fieldValues: [String: String]
  @Binding var checkedOptions: [String: Set<String>]
  @Binding var configValues: [String: String]
  @Binding var configFilePaths: [String: String]
  let bundleRootURL: URL?
  var runAction: (ActionSpec, CommandRenderContext) -> Void
  var saveConfig: (ControlSpec) -> Void
  var loadConfig: (ControlSpec) -> Void
  var persistConfigFilePath: (String, ControlSpec) -> Void
  var fieldValueChanged: (String, ControlSpec) -> Void
  var checkedOptionsChanged: (Set<String>, ControlSpec) -> Void
  var configSettingChanged: (String, ConfigSettingSpec, ControlSpec) -> Void
  var headerAccessory: AnyView?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 8) {
          IconTitleLabel(
            title: page.title,
            iconName: page.iconName,
            iconEmoji: page.iconEmoji,
            defaultSystemImage: "doc.text"
          )
          .font(.largeTitle.weight(.semibold))
          Text(page.summary)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .help(page.summary)
        }

        if let headerAccessory {
          headerAccessory
        }

        ForEach(page.sections) { section in
          SectionRenderer(
            section: section,
            localizationLabels: localizationLabels,
            fieldValues: $fieldValues,
            checkedOptions: $checkedOptions,
            configValues: $configValues,
            configFilePaths: $configFilePaths,
            bundleRootURL: bundleRootURL,
            runAction: runAction,
            saveConfig: saveConfig,
            loadConfig: loadConfig,
            persistConfigFilePath: persistConfigFilePath,
            fieldValueChanged: fieldValueChanged,
            checkedOptionsChanged: checkedOptionsChanged,
            configSettingChanged: configSettingChanged
          )
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(.background)
  }
}
