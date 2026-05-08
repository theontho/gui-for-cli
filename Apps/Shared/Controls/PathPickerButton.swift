import GUIForCLICore
import SwiftUI
import UniformTypeIdentifiers

struct PathPickerButton: View {
  @Binding var path: String
  var labels = BundleLocalizationLabels()
  var canChooseFiles = true
  var canChooseDirectories = true
  var rootURL: URL?
  var onChoose: (URL) -> Void = { _ in }
  @State private var isImportingPath = false
  @State private var pickerErrorMessage = ""
  @State private var isShowingPickerError = false

  var body: some View {
    Button(labels.chooseButtonTitle) {
      choosePath()
    }
    .fileImporter(
      isPresented: $isImportingPath,
      allowedContentTypes: importableContentTypes,
      allowsMultipleSelection: false
    ) { result in
      handleImportedPath(result)
    }
    .alert(labels.pathPickerErrorTitle, isPresented: $isShowingPickerError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(pickerErrorMessage)
    }
  }

  private func choosePath() {
    #if os(macOS)
      let panel = NSOpenPanel()
      panel.canChooseFiles = canChooseFiles
      panel.canChooseDirectories = canChooseDirectories
      panel.allowsMultipleSelection = false
      panel.canCreateDirectories = true
      panel.resolvesAliases = true
      if let initialDirectoryURL = initialDirectoryURL(for: path) {
        panel.directoryURL = initialDirectoryURL
      }

      guard panel.runModal() == .OK, let url = panel.url else {
        return
      }
      path = url.path
      onChoose(url)
    #else
      isImportingPath = true
    #endif
  }

  private func handleImportedPath(_ result: Result<[URL], Error>) {
    do {
      guard let url = try result.get().first else {
        return
      }
      path = url.path
      onChoose(url)
    } catch {
      pickerErrorMessage = error.localizedDescription
      isShowingPickerError = true
    }
  }

  private func initialDirectoryURL(for path: String) -> URL? {
    let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPath.isEmpty else { return nil }

    let expandedPath =
      if let rootURL {
        BundlePathResolver.expand(trimmedPath, rootURL: rootURL)
      } else {
        trimmedPath
      }
    let filePath = (expandedPath as NSString).expandingTildeInPath
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: filePath, isDirectory: &isDirectory) {
      let url = URL(fileURLWithPath: filePath, isDirectory: isDirectory.boolValue)
        .standardizedFileURL
      return isDirectory.boolValue ? url : url.deletingLastPathComponent()
    }

    let parentURL = URL(fileURLWithPath: filePath, isDirectory: false)
      .standardizedFileURL
      .deletingLastPathComponent()
    var parentIsDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: parentURL.path, isDirectory: &parentIsDirectory),
      parentIsDirectory.boolValue
    else {
      return nil
    }
    return parentURL
  }

  private var importableContentTypes: [UTType] {
    var types: [UTType] = []
    if canChooseFiles {
      types.append(.item)
    }
    if canChooseDirectories {
      types.append(.folder)
    }
    return types.isEmpty ? [.item] : types
  }
}
