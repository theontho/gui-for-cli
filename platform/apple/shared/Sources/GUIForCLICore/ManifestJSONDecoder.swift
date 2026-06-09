import Foundation

public struct ManifestJSONDecoder: Sendable {
  public init() {}

  public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let decoder = JSONDecoder()
    return try decoder.decode(T.self, from: strippingComments(from: data))
  }

  public func decode(_ type: CLIBundleManifest.Type, from data: Data) throws -> CLIBundleManifest {
    let manifest = try decodeDecodable(CLIBundleManifest.self, from: data)
    try manifest.validate()
    return manifest
  }

  private func decodeDecodable<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let decoder = JSONDecoder()
    return try decoder.decode(T.self, from: strippingComments(from: data))
  }

  private func strippingComments(from data: Data) -> Data {
    let bytes = [UInt8](data)
    var output: [UInt8] = []
    var index = 0
    var inString = false
    var escaped = false
    var inLineComment = false
    var inBlockComment = false

    while index < bytes.count {
      let byte = bytes[index]
      let nextByte = index + 1 < bytes.count ? bytes[index + 1] : nil

      if inLineComment {
        if byte == 0x0A || byte == 0x0D {
          inLineComment = false
          output.append(byte)
        } else {
          output.append(0x20)
        }
        index += 1
        continue
      }

      if inBlockComment {
        if byte == 0x2A, nextByte == 0x2F {
          output.append(0x20)
          output.append(0x20)
          index += 2
          inBlockComment = false
        } else {
          output.append(byte == 0x0A || byte == 0x0D ? byte : 0x20)
          index += 1
        }
        continue
      }

      if inString {
        output.append(byte)
        if escaped {
          escaped = false
        } else if byte == 0x5C {
          escaped = true
        } else if byte == 0x22 {
          inString = false
        }
        index += 1
        continue
      }

      if byte == 0x22 {
        inString = true
        output.append(byte)
      } else if byte == 0x2F, nextByte == 0x2F {
        output.append(0x20)
        output.append(0x20)
        index += 2
        inLineComment = true
        continue
      } else if byte == 0x2F, nextByte == 0x2A {
        output.append(0x20)
        output.append(0x20)
        index += 2
        inBlockComment = true
        continue
      } else {
        output.append(byte)
      }
      index += 1
    }

    return Data(output)
  }
}
