import Foundation

public enum PlatformProcessCommandResolver {
  public static func resolve(_ command: RenderedCommand) -> RenderedCommand {
    resolve(executable: command.executable, arguments: command.arguments)
  }

  public static func resolve(executable: String, arguments: [String]) -> RenderedCommand {
    #if os(macOS) || os(Linux)
      switch (executable as NSString).pathExtension.lowercased() {
      case "sh":
        return RenderedCommand(executable: "/bin/sh", arguments: [executable] + arguments)
      case "py":
        return RenderedCommand(
          executable: "/usr/bin/env", arguments: ["python3", executable] + arguments)
      default:
        break
      }
      guard executable.hasPrefix("/") else {
        return RenderedCommand(executable: "/usr/bin/env", arguments: [executable] + arguments)
      }
    #endif
    return RenderedCommand(executable: executable, arguments: arguments)
  }
}
