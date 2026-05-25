import Foundation

public struct BundleTestPlan: Codable, Equatable, Sendable {
  public var name: String?
  public var inputs: BundleTestInputs
  public var steps: [BundleTestStep]

  public init(
    name: String? = nil,
    inputs: BundleTestInputs = BundleTestInputs(),
    steps: [BundleTestStep]
  ) {
    self.name = name
    self.inputs = inputs
    self.steps = steps
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decodeIfPresent(String.self, forKey: .name)
    inputs =
      try container.decodeIfPresent(BundleTestInputs.self, forKey: .inputs)
      ?? BundleTestInputs()
    steps = try container.decodeIfPresent([BundleTestStep].self, forKey: .steps) ?? []
  }
}

public struct BundleTestInputs: Codable, Equatable, Sendable {
  public var fieldValues: [String: String]
  public var configValues: [String: String]
  public var checkedOptions: [String: [String]]

  public init(
    fieldValues: [String: String] = [:],
    configValues: [String: String] = [:],
    checkedOptions: [String: [String]] = [:]
  ) {
    self.fieldValues = fieldValues
    self.configValues = configValues
    self.checkedOptions = checkedOptions
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    fieldValues = try container.decodeIfPresent([String: String].self, forKey: .fieldValues) ?? [:]
    configValues =
      try container.decodeIfPresent([String: String].self, forKey: .configValues) ?? [:]
    checkedOptions =
      try container.decodeIfPresent([String: [String]].self, forKey: .checkedOptions) ?? [:]
  }

  public func merging(_ overrides: BundleTestInputs) -> BundleTestInputs {
    BundleTestInputs(
      fieldValues: fieldValues.merging(overrides.fieldValues) { _, override in override },
      configValues: configValues.merging(overrides.configValues) { _, override in override },
      checkedOptions: checkedOptions.merging(overrides.checkedOptions) { _, override in override }
    )
  }
}

public struct BundleTestStep: Codable, Equatable, Identifiable, Sendable {
  public var id: String?
  public var kind: BundleTestStepKind
  public var actionID: String?
  public var pageID: String?
  public var sectionID: String?
  public var controlID: String?
  public var rowID: String?
  public var rowValues: [String: String]
  public var inputs: BundleTestInputs
  public var expectedExitCodes: [Int32]
  public var requiredOutput: [String]
  public var forbiddenOutput: [String]
  public var timeoutSeconds: Double?
  public var continueOnFailure: Bool

  public init(
    id: String? = nil,
    kind: BundleTestStepKind,
    actionID: String? = nil,
    pageID: String? = nil,
    sectionID: String? = nil,
    controlID: String? = nil,
    rowID: String? = nil,
    rowValues: [String: String] = [:],
    inputs: BundleTestInputs = BundleTestInputs(),
    expectedExitCodes: [Int32] = [0],
    requiredOutput: [String] = [],
    forbiddenOutput: [String] = [],
    timeoutSeconds: Double? = nil,
    continueOnFailure: Bool = false
  ) {
    self.id = id
    self.kind = kind
    self.actionID = actionID
    self.pageID = pageID
    self.sectionID = sectionID
    self.controlID = controlID
    self.rowID = rowID
    self.rowValues = rowValues
    self.inputs = inputs
    self.expectedExitCodes = expectedExitCodes
    self.requiredOutput = requiredOutput
    self.forbiddenOutput = forbiddenOutput
    self.timeoutSeconds = timeoutSeconds
    self.continueOnFailure = continueOnFailure
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id)
    kind = try container.decode(BundleTestStepKind.self, forKey: .kind)
    actionID = try container.decodeIfPresent(String.self, forKey: .actionID)
    pageID = try container.decodeIfPresent(String.self, forKey: .pageID)
    sectionID = try container.decodeIfPresent(String.self, forKey: .sectionID)
    controlID = try container.decodeIfPresent(String.self, forKey: .controlID)
    rowID = try container.decodeIfPresent(String.self, forKey: .rowID)
    rowValues = try container.decodeIfPresent([String: String].self, forKey: .rowValues) ?? [:]
    inputs =
      try container.decodeIfPresent(BundleTestInputs.self, forKey: .inputs)
      ?? BundleTestInputs()
    expectedExitCodes =
      try container.decodeIfPresent([Int32].self, forKey: .expectedExitCodes)
      ?? [0]
    requiredOutput = try container.decodeIfPresent([String].self, forKey: .requiredOutput) ?? []
    forbiddenOutput = try container.decodeIfPresent([String].self, forKey: .forbiddenOutput) ?? []
    timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds)
    continueOnFailure =
      try container.decodeIfPresent(Bool.self, forKey: .continueOnFailure) ?? false
  }
}

public enum BundleTestStepKind: String, Codable, Equatable, Sendable {
  case setup
  case action
}
