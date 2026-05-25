import Foundation
import Testing

@testable import GUIForCLICore

@Test func decodesBundleTestPlanWithoutSteps() throws {
  let data = Data(
    """
    {
      "name": "inputs only",
      "inputs": {
        "fieldValues": {
          "sample": "Ada"
        }
      }
    }
    """.utf8)

  let plan = try JSONDecoder().decode(BundleTestPlan.self, from: data)

  #expect(plan.name == "inputs only")
  #expect(plan.inputs.fieldValues == ["sample": "Ada"])
  #expect(plan.steps.isEmpty)
}
