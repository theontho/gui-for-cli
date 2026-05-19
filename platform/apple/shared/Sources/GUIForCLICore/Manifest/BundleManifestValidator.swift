import Foundation

public enum BundleManifestValidator {
  public static func validate(_ manifest: CLIBundleManifest) throws {
    try requireNonEmpty(manifest.id, path: "id")
    if let version = manifest.version {
      try requireNonEmpty(version, path: "version")
    }
    try requireNonEmpty(manifest.displayName, path: "displayName")
    try requireNonEmpty(manifest.summary, path: "summary")
    if let iconPath = manifest.iconPath {
      try validateRelativePath(iconPath, path: "iconPath")
    }
    try validateTextIcon(manifest.textIcon, path: "textIcon")

    guard !manifest.pages.isEmpty || !manifest.pageFiles.isEmpty else {
      throw BundleValidationError.noPages
    }

    try validateUniqueIDs(manifest.setup.steps, path: "setup.steps")
    try validateUniqueIDs(manifest.uninstall.steps, path: "uninstall.steps")
    try validateUniqueIDs(manifest.pages, path: "pages")
    try validateUniqueValues(manifest.pageFiles, path: "pages")
    try validateUniqueExitCodes(manifest.exitCodeReference, path: "exitCodeReference")
    for entry in manifest.exitCodeReference {
      try requireNonEmpty(entry.title, path: "exitCodeReference.\(entry.code).title")
      try requireNonEmpty(entry.summary, path: "exitCodeReference.\(entry.code).summary")
    }

    for setupStep in manifest.setup.steps {
      try validateSetupStep(setupStep, basePrefix: "setup.steps")
    }
    for uninstallStep in manifest.uninstall.steps {
      try validateSetupStep(uninstallStep, basePrefix: "uninstall.steps")
    }

    for pageFile in manifest.pageFiles {
      try validatePageFile(pageFile)
    }

    for page in manifest.pages {
      try validatePage(page)
    }
  }

  private static func validateSetupStep(_ setupStep: SetupStep, basePrefix: String) throws {
    let base = "\(basePrefix).\(setupStep.id)"
    try requireNonEmpty(setupStep.id, path: "\(base).id")
    try requireNonEmpty(setupStep.label, path: "\(base).label")
    try requireNonEmpty(setupStep.value, path: "\(base).value")
    if setupStep.kind == .bundledScript || setupStep.kind == .setupScript {
      try validateRelativePath(setupStep.value, path: "\(base).value")
    }
    if let workingDirectory = setupStep.workingDirectory {
      try validateRelativePath(workingDirectory, path: "\(base).workingDirectory")
    }
    if let toolName = setupStep.toolName {
      try requireNonEmpty(toolName, path: "\(base).toolName")
    }
    if let toolVersion = setupStep.toolVersion {
      try requireNonEmpty(toolVersion, path: "\(base).toolVersion")
    }
    if let toolVersionFile = setupStep.toolVersionFile {
      try validateRelativePath(toolVersionFile, path: "\(base).toolVersionFile")
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
