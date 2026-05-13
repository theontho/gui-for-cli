import Testing

@testable import GUIForCLICLI

@Test func runGreetingUsesProvidedName() {
  #expect(Run.greeting(name: "Ada") == "Hello, Ada from gui-for-cli!")
}
