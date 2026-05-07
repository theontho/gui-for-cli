#!/usr/bin/env swift
import Darwin
import Foundation

private struct Identity {
  let source: String
  let name: String
  let email: String
  let login: String?
  let active: Bool
}

private struct Arguments {
  var choice: Int?
  var updateGitConfig = true
}

private func parseArguments() -> Arguments {
  var arguments = Arguments()
  var iterator = CommandLine.arguments.dropFirst().makeIterator()

  while let argument = iterator.next() {
    switch argument {
    case "--choice":
      if let rawChoice = iterator.next(), let choice = Int(rawChoice) {
        arguments.choice = choice
      } else {
        fputs("--choice requires an integer.\n", stderr)
        exit(1)
      }
    case "--no-update-git-config":
      arguments.updateGitConfig = false
    default:
      fputs("Unknown argument: \(argument)\n", stderr)
      exit(1)
    }
  }

  return arguments
}

private func run(_ command: String, _ arguments: [String]) -> (status: Int32, output: String) {
  let process = Process()
  let output = Pipe()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = [command] + arguments
  process.standardOutput = output
  process.standardError = output

  do {
    try process.run()
    process.waitUntilExit()
  } catch {
    return (1, error.localizedDescription)
  }

  let data = output.fileHandleForReading.readDataToEndOfFile()
  return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

private func gitConfig(_ key: String) -> String {
  let result = run("git", ["config", key])
  guard result.status == 0 else { return "" }
  return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func parseGitHubAccounts(_ output: String) -> [(login: String, active: Bool)] {
  var accounts: [(login: String, active: Bool)] = []
  var currentIndex: Int?

  for line in output.split(whereSeparator: \.isNewline).map(String.init) {
    if let marker = line.range(of: " account ") {
      let suffix = line[marker.upperBound...]
      if let login = suffix.split(whereSeparator: { $0 == " " || $0 == "(" }).first {
        accounts.append((String(login), false))
        currentIndex = accounts.count - 1
      }
      continue
    }

    if line.contains("Active account:") && line.contains("true"), let currentIndex {
      accounts[currentIndex].active = true
    }
  }

  return accounts
}

private func jsonObject(from text: String) -> [String: Any]? {
  guard let data = text.data(using: .utf8) else { return nil }
  return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

private func githubIdentity(username: String, active: Bool) -> Identity {
  let response = run("gh", ["api", "users/\(username)"])
  let userInfo = response.status == 0 ? jsonObject(from: response.output) : nil
  let login = userInfo?["login"] as? String ?? username
  let name = userInfo?["name"] as? String ?? login
  let publicEmail = userInfo?["email"] as? String
  let id = userInfo?["id"] as? Int
  let email =
    publicEmail ?? id.map { "\($0)+\(login)@users.noreply.github.com" }
    ?? "\(login)@users.noreply.github.com"
  let source = active ? "GitHub active account (\(username))" : "GitHub account (\(username))"

  return Identity(source: source, name: name, email: email, login: login, active: active)
}

private func githubIdentities() -> [Identity] {
  guard run("gh", ["--version"]).status == 0 else { return [] }

  let status = run("gh", ["auth", "status", "--hostname", "github.com"])
  let accounts = parseGitHubAccounts(status.output)
  var seen: Set<String> = []
  var identities: [Identity] = []

  for account in accounts.sorted(by: { $0.active && !$1.active }) {
    if seen.insert(account.login).inserted {
      identities.append(githubIdentity(username: account.login, active: account.active))
    }
  }

  return identities
}

private func availableIdentities() -> [Identity] {
  var identities = githubIdentities()
  let name = gitConfig("user.name")
  let email = gitConfig("user.email")

  if !name.isEmpty || !email.isEmpty {
    identities.append(
      Identity(source: "Local Git Config", name: name, email: email, login: nil, active: false)
    )
  }

  return identities
}

private func selectIdentity(from identities: [Identity], choice: Int?) -> Identity {
  let defaultChoice = identities.firstIndex(where: \.active).map { $0 + 1 } ?? 1
  let selectedChoice: Int

  if let choice {
    selectedChoice = choice
  } else if isatty(STDIN_FILENO) == 1 {
    print(
      "Choose an identity to register in .dev_id (1-\(identities.count)) [\(defaultChoice)]: ",
      terminator: "")
    selectedChoice = Int(readLine() ?? "") ?? defaultChoice
  } else {
    selectedChoice = defaultChoice
  }

  guard identities.indices.contains(selectedChoice - 1) else {
    fputs("Invalid choice.\n", stderr)
    exit(1)
  }

  return identities[selectedChoice - 1]
}

let arguments = parseArguments()
let identities = availableIdentities()

guard !identities.isEmpty else {
  fputs("No git or GitHub identity found. Configure git or login to gh.\n", stderr)
  exit(1)
}

print("Available Identities:")
for (index, identity) in identities.enumerated() {
  print("\(index + 1)) \(identity.source): \(identity.name) <\(identity.email)>")
}

let selected = selectIdentity(from: identities, choice: arguments.choice)
try "name=\(selected.name)\nemail=\(selected.email)\n".write(
  toFile: ".dev_id",
  atomically: true,
  encoding: .utf8
)
print("Registered in .dev_id using \(selected.source)")

if arguments.updateGitConfig {
  _ = run("git", ["config", "user.name", selected.name])
  _ = run("git", ["config", "user.email", selected.email])
  print("Updated repository git identity to match .dev_id")
}
