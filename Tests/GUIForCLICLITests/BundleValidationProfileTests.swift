import Foundation
import GUIForCLICore
import Testing

@testable import GUIForCLICLI

@Test func releaseProfileRejectsInlinePages() {
  let loaded = sampleLoadedBundle(pageFiles: [])
  let errors = BundleValidationProfile.release.validationErrors(for: loaded)
  #expect(errors.count == 1)
}

@Test func releaseProfileAcceptsPageFileManifests() {
  let loaded = sampleLoadedBundle(pageFiles: ["main.json"])
  let errors = BundleValidationProfile.release.validationErrors(for: loaded)
  #expect(errors.isEmpty)
}

@Test func developmentProfileAllowsInlinePages() {
  let loaded = sampleLoadedBundle(pageFiles: [])
  let errors = BundleValidationProfile.development.validationErrors(for: loaded)
  #expect(errors.isEmpty)
}

@Test func releaseProfileForcesStrictLocalesAndNoSkip() {
  #expect(BundleValidationProfile.release.localeWarningsAreErrors)
  #expect(BundleValidationProfile.release.allowsSkippingLocales == false)
  #expect(BundleValidationProfile.development.localeWarningsAreErrors == false)
  #expect(BundleValidationProfile.development.allowsSkippingLocales)
}

private func sampleLoadedBundle(pageFiles: [String]) -> LoadedBundle {
  let manifest = CLIBundleManifest(
    id: "sample",
    displayName: "Sample",
    summary: "Sample bundle",
    iconName: "terminal",
    pages: [
      BundlePage(
        id: "main",
        title: "Main",
        summary: "Main page",
        sections: [
          PageSection(id: "general")
        ])
    ],
    pageFiles: pageFiles)
  return LoadedBundle(
    manifest: manifest,
    manifestURL: URL(fileURLWithPath: "/tmp/manifest.json"),
    rootURL: URL(fileURLWithPath: "/tmp"),
    isTemporary: false)
}
