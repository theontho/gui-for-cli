import GUIForCLICore
import SwiftUI

/// SwiftUI view modifiers that derive a coherent set of accessibility
/// metadata directly from manifest specs. Apply these at every
/// manifest-driven view to avoid hand-rolling accessibilityLabel /
/// accessibilityHint / accessibilityIdentifier at each call site.
///
/// Localization: the `label`, `title`, `tooltip`, `subtitle`, and
/// `summary` fields on the specs have already been substituted with
/// localized strings by `BundleSourceLoader` before reaching the
/// renderers, so passing them straight to AX modifiers yields a fully
/// localized accessibility tree.
extension View {
  /// Annotate any control widget (TextField, Picker, Toggle, …) with
  /// its manifest label as the AX label, the tooltip as the hint, and
  /// `control.<id>` as the stable identifier.
  func axControl(_ control: ControlSpec) -> some View {
    accessibilityLabel(Text(control.label))
      .accessibilityHint(Text(control.tooltip ?? ""))
      .accessibilityIdentifier(AccessibilityIdentifier.control(control.id))
  }

  /// Annotate an action button (Run / destructive / secondary) using
  /// the action's localized title + tooltip. When the button is
  /// disabled the `disabledTooltip` (if provided) is preferred so
  /// VoiceOver explains *why* it's disabled.
  func axAction(_ action: ActionSpec, isDisabled: Bool = false) -> some View {
    let hint: String
    if isDisabled, let reason = action.disabledTooltip?.nonEmpty {
      hint = reason
    } else {
      hint = action.tooltip ?? ""
    }
    return accessibilityLabel(Text(action.title))
      .accessibilityHint(Text(hint))
      .accessibilityIdentifier(AccessibilityIdentifier.action(action.id))
      .accessibilityAddTraits(.isButton)
  }

  /// Annotate a single option inside a multi-option control (checkbox
  /// row, radio, library list row).
  func axOption(_ option: ControlOption, in control: ControlSpec) -> some View {
    accessibilityIdentifier(
      AccessibilityIdentifier.option(controlID: control.id, optionID: option.id))
  }

  /// Annotate a section container so VoiceOver groups its children
  /// under a labeled rotor entry.
  func axSection(_ section: PageSection) -> some View {
    accessibilityLabel(Text(section.title ?? section.id))
      .accessibilityHint(Text(section.subtitle ?? ""))
      .accessibilityIdentifier(AccessibilityIdentifier.section(section.id))
  }

  /// Annotate the page title and surrounding container.
  func axPage(_ page: BundlePage) -> some View {
    accessibilityLabel(Text(page.title))
      .accessibilityHint(Text(page.summary))
      .accessibilityIdentifier(AccessibilityIdentifier.page(page.id))
  }

  /// Mark a piece of text as a heading at the given level so the
  /// VoiceOver rotor can jump between page / section titles.
  func axHeading(_ level: AccessibilityHeadingLevel) -> some View {
    accessibilityAddTraits(.isHeader)
      .accessibilityHeading(level)
  }
}
