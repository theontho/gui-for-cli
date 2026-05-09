import Foundation

public enum BundleManifestValidator {
  public static func validate(_ manifest: CLIBundleManifest) throws {
    try requireNonEmpty(manifest.id, path: "id")
    try requireNonEmpty(manifest.displayName, path: "displayName")
    try requireNonEmpty(manifest.summary, path: "summary")
    if let iconPath = manifest.iconPath {
      try validateRelativePath(iconPath, path: "iconPath")
    }
    if let iconEmoji = manifest.iconEmoji {
      try requireNonEmpty(iconEmoji, path: "iconEmoji")
    }

    guard !manifest.pages.isEmpty || !manifest.pageFiles.isEmpty else {
      throw BundleValidationError.noPages
    }

    try validateUniqueIDs(manifest.setup.steps, path: "setup.steps")
    try validateUniqueIDs(manifest.pages, path: "pages")
    try validateUniqueValues(manifest.pageFiles, path: "pages")
    try validateUniqueExitCodes(manifest.exitCodeReference, path: "exitCodeReference")
    for entry in manifest.exitCodeReference {
      try requireNonEmpty(entry.title, path: "exitCodeReference.\(entry.code).title")
      try requireNonEmpty(entry.summary, path: "exitCodeReference.\(entry.code).summary")
    }

    for setupStep in manifest.setup.steps {
      try validateSetupStep(setupStep)
    }

    for pageFile in manifest.pageFiles {
      try validatePageFile(pageFile)
    }

    for page in manifest.pages {
      try validatePage(page)
    }
  }

  private static func validateSetupStep(_ setupStep: SetupStep) throws {
    let base = "setup.steps.\(setupStep.id)"
    try requireNonEmpty(setupStep.id, path: "\(base).id")
    try requireNonEmpty(setupStep.label, path: "\(base).label")
    try requireNonEmpty(setupStep.value, path: "\(base).value")
    if setupStep.kind == .bundledScript || setupStep.kind == .setupScript {
      try validateRelativePath(setupStep.value, path: "\(base).value")
    }
    if let workingDirectory = setupStep.workingDirectory {
      try validateRelativePath(workingDirectory, path: "\(base).workingDirectory")
    }
  }

  private static func validatePageFile(_ pageFile: String) throws {
    try requireNonEmpty(pageFile, path: "pages")
    try validateRelativePath(pageFile, path: "pages")
    if pageFile.contains("/") {
      throw BundleValidationError.invalidRelativePath(path: "pages", value: pageFile)
    }
  }
}
