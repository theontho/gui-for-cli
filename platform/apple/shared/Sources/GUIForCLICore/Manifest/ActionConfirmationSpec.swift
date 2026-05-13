import Foundation

public struct ActionConfirmationSpec: Codable, Equatable, Sendable {
  public var title: String
  public var message: String?
  public var confirmButtonTitle: String
  public var cancelButtonTitle: String
  public var requiredText: String?
  public var prompt: String?

  public init(
    title: String,
    message: String? = nil,
    confirmButtonTitle: String = "Continue",
    cancelButtonTitle: String = "Cancel",
    requiredText: String? = nil,
    prompt: String? = nil
  ) {
    self.title = title
    self.message = message
    self.confirmButtonTitle = confirmButtonTitle
    self.cancelButtonTitle = cancelButtonTitle
    self.requiredText = requiredText
    self.prompt = prompt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decode(String.self, forKey: .title)
    message = try container.decodeIfPresent(String.self, forKey: .message)
    confirmButtonTitle =
      try container.decodeIfPresent(String.self, forKey: .confirmButtonTitle) ?? "Continue"
    cancelButtonTitle =
      try container.decodeIfPresent(String.self, forKey: .cancelButtonTitle) ?? "Cancel"
    requiredText = try container.decodeIfPresent(String.self, forKey: .requiredText)
    prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
  }

  private enum CodingKeys: String, CodingKey {
    case title
    case message
    case confirmButtonTitle
    case cancelButtonTitle
    case requiredText
    case prompt
  }
}
