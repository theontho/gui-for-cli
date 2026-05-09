import GUIForCLICore
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct StandardOptionsSection: View {
  let options: [BundleLocalizationOption]
  let labels: BundleLocalizationLabels
  let selectedCode: String
  let usingSystemDefault: Bool
  let selectedIconSet: BundleIconSet
  let selectedColorTheme: BundleColorTheme
  var onSelectExplicit: (String) -> Void
  var onSelectSystemDefault: () -> Void
  var onSelectIconSet: (BundleIconSet) -> Void
  var onSelectColorTheme: (BundleColorTheme) -> Void

  @State private var isPresenting = false
  @State private var searchText = ""

  private var currentName: String {
    options.first { $0.code == selectedCode }?.displayName ?? selectedCode
  }

  private var buttonLabel: String {
    usingSystemDefault
      ? "\(labels.languageSystemDefaultLabel) — \(currentName)"
      : currentName
  }

  private var filteredOptions: [BundleLocalizationOption] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let sorted = Self.sorted(options)
    if query.isEmpty { return sorted }
    return sorted.filter { option in
      option.displayName.lowercased().contains(query)
        || option.code.lowercased().contains(query)
    }
  }

  private static func sorted(_ options: [BundleLocalizationOption]) -> [BundleLocalizationOption] {
    let englishMatches = options.filter { isEnglish($0.code) }
    let others = options.filter { !isEnglish($0.code) }
      .sorted { lhs, rhs in
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
      }
    return englishMatches + others
  }

  private static func isEnglish(_ code: String) -> Bool {
    let lower = code.lowercased()
    return lower == "en" || lower.hasPrefix("en-") || lower.hasPrefix("en_")
  }

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        if options.count > 1 {
          languagePickerRow
        }
        pickerRow(title: labels.iconSetPickerLabel) {
          Picker(labels.iconSetPickerLabel, selection: iconSetBinding) {
            Text(labels.iconSetSwiftSymbolsLabel).tag(BundleIconSet.platform)
            Text(labels.iconSetEmojiLabel).tag(BundleIconSet.emoji)
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(maxWidth: 280, alignment: .leading)
        }
        pickerRow(title: labels.colorThemePickerLabel) {
          Picker(labels.colorThemePickerLabel, selection: colorThemeBinding) {
            Text(labels.colorThemeSystemLabel).tag(BundleColorTheme.system)
            Text(labels.colorThemeLightLabel).tag(BundleColorTheme.light)
            Text(labels.colorThemeDarkLabel).tag(BundleColorTheme.dark)
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(maxWidth: 360, alignment: .leading)
        }
      }
    } label: {
      Label(labels.standardOptionsSectionTitle, systemImage: "slider.horizontal.3")
    }
  }

  private var languagePickerRow: some View {
    pickerRow(title: labels.languagePickerLabel) {
      Button {
        isPresenting.toggle()
      } label: {
        HStack(spacing: 6) {
          Text(buttonLabel)
            .lineLimit(1)
            .truncationMode(.tail)
          Spacer(minLength: 4)
          Image(systemName: "chevron.down")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .buttonStyle(.bordered)
      .frame(maxWidth: 280, alignment: .leading)
      .popover(isPresented: $isPresenting, arrowEdge: .bottom) {
        languageList
      }
    }
  }

  private func pickerRow<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    LeadingFormRow {
      Text(title)
        .font(.headline)
    } content: {
      content()
    }
  }

  private var iconSetBinding: Binding<BundleIconSet> {
    Binding(
      get: { selectedIconSet },
      set: { onSelectIconSet($0) })
  }

  private var colorThemeBinding: Binding<BundleColorTheme> {
    Binding(
      get: { selectedColorTheme },
      set: { onSelectColorTheme($0) })
  }

  private var languageList: some View {
    VStack(alignment: .leading, spacing: 0) {
      TextField(labels.languageSearchPlaceholder, text: $searchText)
        .textFieldStyle(.roundedBorder)
        .padding(8)
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          languageRow(
            title: labels.languageSystemDefaultLabel,
            subtitle: nil,
            isSelected: usingSystemDefault,
            action: {
              isPresenting = false
              onSelectSystemDefault()
            })
          Divider()
          ForEach(filteredOptions) { option in
            languageRow(
              title: option.displayName,
              subtitle: option.code,
              isSelected: !usingSystemDefault && option.code == selectedCode,
              action: {
                isPresenting = false
                onSelectExplicit(option.code)
              })
          }
        }
      }
      .frame(minWidth: 280, maxHeight: 360)
    }
    .frame(minWidth: 280)
  }

  @ViewBuilder
  private func languageRow(
    title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: isSelected ? "checkmark" : "circle")
          .foregroundStyle(isSelected ? Color.accentColor : .secondary)
          .frame(width: 16)
        VStack(alignment: .leading, spacing: 1) {
          Text(title)
          if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
