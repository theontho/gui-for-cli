import Foundation

extension String {
  /// App chrome text (not bundle text) from `Localizable.xcstrings`, looked up
  /// in `locale`'s language so it follows the bundle's language picker.
  init(chrome key: String.LocalizationValue, locale: Locale) {
    self.init(localized: LocalizedStringResource(key, locale: locale))
  }
}
