import Foundation
import Testing

@testable import GUIForCLICore

@Test func matchLocalizationCodeExactMatch() {
  let options = [
    BundleLocalizationOption(code: "en", displayName: "English"),
    BundleLocalizationOption(code: "ja", displayName: "日本語"),
    BundleLocalizationOption(code: "zh-Hant", displayName: "繁體中文"),
  ]
  #expect(
    BundleSourceLoader.matchLocalizationCode(preferences: ["ja"], options: options) == "ja")
  #expect(
    BundleSourceLoader.matchLocalizationCode(preferences: ["zh-Hant"], options: options)
      == "zh-Hant")
}

@Test func matchLocalizationCodeRegionStripped() {
  let options = [
    BundleLocalizationOption(code: "en", displayName: "English"),
    BundleLocalizationOption(code: "pt", displayName: "Português"),
  ]
  #expect(
    BundleSourceLoader.matchLocalizationCode(preferences: ["pt-BR"], options: options) == "pt")
  #expect(
    BundleSourceLoader.matchLocalizationCode(preferences: ["en-US"], options: options) == "en")
}

@Test func matchLocalizationCodeChineseScriptFallback() {
  let options = [
    BundleLocalizationOption(code: "zh-Hans", displayName: "简体中文"),
    BundleLocalizationOption(code: "zh-Hant", displayName: "繁體中文"),
  ]
  #expect(
    BundleSourceLoader.matchLocalizationCode(preferences: ["zh-CN"], options: options)
      == "zh-Hans")
  #expect(
    BundleSourceLoader.matchLocalizationCode(preferences: ["zh-TW"], options: options)
      == "zh-Hant")
  #expect(
    BundleSourceLoader.matchLocalizationCode(preferences: ["zh-HK"], options: options)
      == "zh-Hant")
  #expect(
    BundleSourceLoader.matchLocalizationCode(preferences: ["zh-SG"], options: options)
      == "zh-Hans")
}

@Test func matchLocalizationCodeReturnsNilWhenNoMatch() {
  let options = [BundleLocalizationOption(code: "en", displayName: "English")]
  #expect(BundleSourceLoader.matchLocalizationCode(preferences: ["fr"], options: options) == nil)
  #expect(BundleSourceLoader.matchLocalizationCode(preferences: [], options: options) == nil)
  #expect(
    BundleSourceLoader.matchLocalizationCode(preferences: ["  "], options: options) == nil)
}

@Test func matchLocalizationCodePrefersFirstPreference() {
  let options = [
    BundleLocalizationOption(code: "en", displayName: "English"),
    BundleLocalizationOption(code: "ja", displayName: "日本語"),
  ]
  // First preference wins even when later preferences would also match.
  #expect(
    BundleSourceLoader.matchLocalizationCode(preferences: ["ja", "en"], options: options) == "ja"
  )
  #expect(
    BundleSourceLoader.matchLocalizationCode(preferences: ["fr", "ja"], options: options) == "ja"
  )
}
