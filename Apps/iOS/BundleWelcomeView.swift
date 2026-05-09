import GUIForCLICore
import SwiftUI
import UniformTypeIdentifiers

/// Shown on iOS when no bundle has been loaded. Lets the user import a bundle
/// folder or `manifest.json` from the Files app.
struct BundleWelcomeView: View {
  let onBundleImported: (URL) -> Void

  @State private var isPickerPresented = false
  @State private var importError: String? = nil

  var body: some View {
    NavigationStack {
      VStack(spacing: 32) {
        Spacer()

        Image(systemName: "terminal")
          .font(.system(size: 80, weight: .thin))
          .foregroundStyle(.tint)

        VStack(spacing: 10) {
          Text("GUI for CLI")
            .font(.title.weight(.bold))
          Text(
            "Browse and configure CLI tool bundles.\nImport a bundle folder or manifest.json to get started."
          )
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal)
        }

        if let error = importError {
          Text(error)
            .font(.footnote)
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }

        Button {
          importError = nil
          isPickerPresented = true
        } label: {
          Label("Open Bundle", systemImage: "folder.badge.plus")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, 40)

        Spacer()
      }
      .navigationTitle("GUI for CLI")
      .navigationBarTitleDisplayMode(.inline)
      .fileImporter(
        isPresented: $isPickerPresented,
        allowedContentTypes: [
          .folder,
          .json,
        ],
        allowsMultipleSelection: false
      ) { result in
        handleImportResult(result)
      }
    }
  }

  private func handleImportResult(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      guard let url = urls.first else { return }
      importBundle(from: url)
    case .failure(let error):
      importError = error.localizedDescription
    }
  }

  private func importBundle(from url: URL) {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }

    do {
      let destination = try BundleImporter.copyToSandbox(from: url)
      onBundleImported(destination)
    } catch {
      importError = error.localizedDescription
    }
  }
}
