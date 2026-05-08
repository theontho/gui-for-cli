import Foundation
import Testing

@testable import GUIForCLICore

@Test func plansSetupScriptAndPixiCommands() throws {
  let directory = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let scripts = directory.appendingPathComponent("scripts", isDirectory: true)
  try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
  let scriptURL = scripts.appendingPathComponent("setup.sh", isDirectory: false)
  try "#!/bin/sh\necho setup\n".write(to: scriptURL, atomically: true, encoding: .utf8)

  let data = Data(
    """
    {
      "id": "setup-test",
      "displayName": "Setup Test",
      "summary": "Exercises setup planning.",
      "iconPath": "Assets/icon.png",
      "setup": {
        "steps": [
          {
            "id": "script",
            "label": "Install",
            "kind": "setupScript",
            "value": "scripts/setup.sh",
            "arguments": ["--install-dir", "{{bundleRoot}}/app"],
            "environment": {"CACHE_DIR": "{{bundleRoot}}/.cache"}
          },
          {
            "id": "pixi",
            "label": "Install Pixi environment",
            "kind": "pixiInstall",
            "value": "pixi",
            "workingDirectory": "app"
          },
          {
            "id": "deps",
            "label": "Check dependencies",
            "kind": "pixiRun",
            "value": "deps-check",
            "optional": true
          }
        ]
      },
      "pages": [
        {
          "id": "main",
          "title": "Main",
          "summary": "Main page.",
          "systemImage": "terminal",
          "sections": [{"id":"main-section"}]
        }
      ]
    }
    """.utf8)
  let manifest = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: data)

  let commands = try SetupCommandPlanner().plan(for: manifest, rootURL: directory)

  #expect(commands[0].arguments == [scriptURL.path, "--install-dir", "\(directory.path)/app"])
  #expect(commands[0].environment["CACHE_DIR"] == "\(directory.path)/.cache")
  #expect(commands[1].arguments == ["pixi", "install"])
  #expect(commands[1].workingDirectory.path == directory.appendingPathComponent("app").path)
  #expect(commands[2].arguments == ["pixi", "run", "deps-check"])
  #expect(commands[2].optional)
}

@Test func rejectsUnsafeSetupAndIconPaths() throws {
  let unsafeIcon = Data(
    """
    {
      "id": "unsafe-icon",
      "displayName": "Unsafe Icon",
      "summary": "Bad icon.",
      "iconPath": "../icon.png",
      "pages": [{"id":"main","title":"Main","summary":"Main page.","sections":[{"id":"main-section"}]}]
    }
    """.utf8)
  #expect(throws: BundleValidationError.invalidRelativePath(path: "iconPath", value: "../icon.png"))
  {
    _ = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: unsafeIcon)
  }

  let unsafeScript = Data(
    """
    {
      "id": "unsafe-script",
      "displayName": "Unsafe Script",
      "summary": "Bad script.",
      "setup": {
        "steps": [
          {"id":"setup","label":"Setup","kind":"setupScript","value":"../setup.sh"}
        ]
      },
      "pages": [{"id":"main","title":"Main","summary":"Main page.","sections":[{"id":"main-section"}]}]
    }
    """.utf8)
  #expect(
    throws: BundleValidationError.invalidRelativePath(
      path: "setup.steps.setup.value", value: "../setup.sh")
  ) {
    _ = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: unsafeScript)
  }

  let unsafeDataSource = Data(
    """
    {
      "id": "unsafe-data-source",
      "displayName": "Unsafe Data Source",
      "summary": "Bad data source.",
      "pages": [
        {
          "id":"main",
          "title":"Main",
          "summary":"Main page.",
          "sections":[
            {
              "id":"main-section",
              "controls":[
                {
                  "id":"refs",
                  "label":"Refs",
                  "kind":"dropdown",
                  "dataSource":{"path":"../list.sh"}
                }
              ]
            }
          ]
        }
      ]
    }
    """.utf8)
  #expect(
    throws: BundleValidationError.invalidRelativePath(
      path: "pages.main.sections.main-section.controls.refs.dataSource.path", value: "../list.sh")
  ) {
    _ = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: unsafeDataSource)
  }
}

@Test func rejectsTemplatedDataSourcePaths() throws {
  let unsafeDataSource = Data(
    """
    {
      "id": "unsafe-data-source-template",
      "displayName": "Unsafe Data Source Template",
      "summary": "Bad data source.",
      "pages": [
        {
          "id":"main",
          "title":"Main",
          "summary":"Main page.",
          "sections":[
            {
              "id":"main-section",
              "controls":[
                {
                  "id":"refs",
                  "label":"Refs",
                  "kind":"dropdown",
                  "dataSource":{"path":"{{home}}/list.sh"}
                }
              ]
            }
          ]
        }
      ]
    }
    """.utf8)
  #expect(
    throws: BundleValidationError.invalidRelativePath(
      path: "pages.main.sections.main-section.controls.refs.dataSource.path",
      value: "{{home}}/list.sh")
  ) {
    _ = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: unsafeDataSource)
  }

  let unsafeWorkingDirectory = Data(
    """
    {
      "id": "unsafe-data-source-working-directory",
      "displayName": "Unsafe Data Source Working Directory",
      "summary": "Bad data source.",
      "pages": [
        {
          "id":"main",
          "title":"Main",
          "summary":"Main page.",
          "sections":[
            {
              "id":"main-section",
              "controls":[
                {
                  "id":"refs",
                  "label":"Refs",
                  "kind":"dropdown",
                  "dataSource":{"path":"scripts/list.sh","workingDirectory":"~/scripts"}
                }
              ]
            }
          ]
        }
      ]
    }
    """.utf8)
  #expect(
    throws: BundleValidationError.invalidRelativePath(
      path: "pages.main.sections.main-section.controls.refs.dataSource.workingDirectory",
      value: "~/scripts")
  ) {
    _ = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: unsafeWorkingDirectory)
  }
}

@Test func acceptsNumericConditionOperators() throws {
  let payload = Data(
    """
    {
      "id": "numeric-conditions",
      "displayName": "Numeric Conditions",
      "summary": "Tests greaterThan support.",
      "pages": [
        {
          "id": "main",
          "title": "Main",
          "summary": "Main page.",
          "sections": [
            {
              "id": "main-section",
              "actions": [
                {
                  "id": "act",
                  "title": "Act",
                  "visibleWhen": [
                    {"placeholder": "bam_path.fileSizeGB", "greaterThan": "0.5"},
                    {"placeholder": "free_space_gb", "greaterThanOrEqual": "100"}
                  ],
                  "precheck": {
                    "diskSpaceGB": "{{bam_path.fileSizeGB}} * 6",
                    "diskSpacePath": "{{out_dir}}"
                  },
                  "command": {"executable": "tool", "arguments": ["go"]}
                }
              ]
            }
          ]
        }
      ]
    }
    """.utf8)
  let manifest = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: payload)
  let action = manifest.pages[0].sections[0].actions[0]
  #expect(action.visibleWhen[0].greaterThan == "0.5")
  #expect(action.visibleWhen[1].greaterThanOrEqual == "100")
  #expect(action.precheck?.diskSpaceGB == "{{bam_path.fileSizeGB}} * 6")
  #expect(action.precheck?.diskSpacePath == "{{out_dir}}")
}

@Test func rejectsVisibleWhenWithoutConditionOperator() throws {
  let invalidCondition = Data(
    """
    {
      "id": "invalid-visible-when",
      "displayName": "Invalid Visible When",
      "summary": "Bad condition.",
      "pages": [
        {
          "id":"main",
          "title":"Main",
          "summary":"Main page.",
          "sections":[
            {
              "id":"main-section",
              "controls":[
                {
                  "id":"refs",
                  "label":"Refs",
                  "kind":"libraryList",
                  "rowActions":[
                    {
                      "id":"verify",
                      "title":"Verify",
                      "visibleWhen":[{"placeholder":"row.status"}],
                      "command":{"executable":"tool","arguments":["verify"]}
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
    """.utf8)
  #expect(
    throws: BundleValidationError.emptyField(
      path:
        "pages.main.sections.main-section.controls.refs.rowActions.verify.visibleWhen.0")
  ) {
    _ = try ManifestJSONDecoder().decode(CLIBundleManifest.self, from: invalidCondition)
  }
}
