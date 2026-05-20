#!/usr/bin/env swift

import AppKit
import Foundation

enum BadgeKind: String {
  case apple
  case none
  case web
}

struct Options {
  let baseIcon: String
  let outputICNS: String?
  let outputPNG: String?
  let badge: BadgeKind
}

enum IconGeneratorError: Error, CustomStringConvertible {
  case invalidArguments(String)
  case missingBaseIcon(String)
  case unreadableBaseIcon(String)
  case couldNotEncodePNG(String)
  case iconutilFailed(Int32)

  var description: String {
    switch self {
    case let .invalidArguments(message):
      return message
    case let .missingBaseIcon(path):
      return "Base icon does not exist: \(path)"
    case let .unreadableBaseIcon(path):
      return "Could not load base icon: \(path)"
    case let .couldNotEncodePNG(path):
      return "Could not encode PNG output: \(path)"
    case let .iconutilFailed(code):
      return "iconutil failed with exit code \(code)"
    }
  }
}

do {
  try main()
} catch {
  fputs("\(error)\n", stderr)
  exit(1)
}

func main() throws {
  let options = try parseOptions(arguments: Array(CommandLine.arguments.dropFirst()))
  let baseIconURL = URL(fileURLWithPath: options.baseIcon)

  guard FileManager.default.fileExists(atPath: baseIconURL.path) else {
    throw IconGeneratorError.missingBaseIcon(baseIconURL.path)
  }

  guard let baseImage = NSImage(contentsOf: baseIconURL) else {
    throw IconGeneratorError.unreadableBaseIcon(baseIconURL.path)
  }

  if let outputPNG = options.outputPNG {
    let outputURL = URL(fileURLWithPath: outputPNG)
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: nil)
    let pixelSize = max(pixelWidth(for: baseImage), pixelHeight(for: baseImage))
    let image = renderIcon(baseImage: baseImage, pixelSize: pixelSize, badge: options.badge)
    try writePNG(image: image, to: outputURL)
  }

  if let outputICNS = options.outputICNS {
    let outputURL = URL(fileURLWithPath: outputICNS)
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: nil)
    try writeICNS(baseImage: baseImage, badge: options.badge, to: outputURL)
  }
}

func parseOptions(arguments: [String]) throws -> Options {
  var baseIcon: String?
  var outputICNS: String?
  var outputPNG: String?
  var badge: BadgeKind = .none

  var index = 0
  while index < arguments.count {
    let argument = arguments[index]
    switch argument {
    case "--base-icon":
      index += 1
      baseIcon = try readValue(arguments: arguments, index: index, flag: argument)
    case "--output-icns":
      index += 1
      outputICNS = try readValue(arguments: arguments, index: index, flag: argument)
    case "--output-png":
      index += 1
      outputPNG = try readValue(arguments: arguments, index: index, flag: argument)
    case "--badge":
      index += 1
      let raw = try readValue(arguments: arguments, index: index, flag: argument)
      guard let parsed = BadgeKind(rawValue: raw) else {
        throw IconGeneratorError.invalidArguments("Unsupported badge: \(raw)")
      }
      badge = parsed
    default:
      throw IconGeneratorError.invalidArguments("Unknown option: \(argument)")
    }
    index += 1
  }

  guard let baseIcon else {
    throw IconGeneratorError.invalidArguments("Missing required --base-icon")
  }
  guard outputICNS != nil || outputPNG != nil else {
    throw IconGeneratorError.invalidArguments("Specify at least one of --output-icns or --output-png")
  }

  return Options(baseIcon: baseIcon, outputICNS: outputICNS, outputPNG: outputPNG, badge: badge)
}

func readValue(arguments: [String], index: Int, flag: String) throws -> String {
  guard arguments.indices.contains(index) else {
    throw IconGeneratorError.invalidArguments("Missing value for \(flag)")
  }
  return arguments[index]
}

func pixelWidth(for image: NSImage) -> Int {
  image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width ?? Int(image.size.width)
}

func pixelHeight(for image: NSImage) -> Int {
  image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.height ?? Int(image.size.height)
}

func renderIcon(baseImage: NSImage, pixelSize: Int, badge: BadgeKind) -> NSImage {
  let size = NSSize(width: pixelSize, height: pixelSize)
  let image = NSImage(size: size)
  image.lockFocus()
  defer { image.unlockFocus() }

  guard let context = NSGraphicsContext.current?.cgContext else {
    return image
  }

  NSGraphicsContext.current?.imageInterpolation = .high
  let bounds = CGRect(origin: .zero, size: size)
  baseImage.draw(in: bounds)

  guard badge != .none else { return image }

  let inset = CGFloat(pixelSize) * 0.055
  let diameter = CGFloat(pixelSize) * 0.34
  let badgeRect = CGRect(
    x: inset,
    y: CGFloat(pixelSize) - diameter - inset,
    width: diameter,
    height: diameter)

  context.saveGState()
  let shadow = NSShadow()
  shadow.shadowBlurRadius = diameter * 0.18
  shadow.shadowOffset = NSSize(width: 0, height: -diameter * 0.04)
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
  shadow.set()

  NSColor(
    calibratedRed: 0.97,
    green: 0.98,
    blue: 1.0,
    alpha: 0.96
  ).setFill()
  NSBezierPath(ovalIn: badgeRect).fill()
  context.restoreGState()

  NSColor.white.withAlphaComponent(0.92).setStroke()
  let stroke = NSBezierPath(ovalIn: badgeRect.insetBy(dx: diameter * 0.025, dy: diameter * 0.025))
  stroke.lineWidth = max(1, diameter * 0.05)
  stroke.stroke()

  drawBadgeGlyph(in: badgeRect, badge: badge)
  return image
}

func drawBadgeGlyph(in badgeRect: CGRect, badge: BadgeKind) {
  let glyph: String
  let font: NSFont

  switch badge {
  case .apple:
    glyph = "\u{F8FF}"
    font = NSFont.systemFont(ofSize: badgeRect.height * 0.58, weight: .bold)
  case .web:
    glyph = "🌐"
    font = NSFont.systemFont(ofSize: badgeRect.height * 0.52)
  case .none:
    return
  }

  let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.black.withAlphaComponent(0.82),
  ]
  let attributed = NSAttributedString(string: glyph, attributes: attributes)
  let textSize = attributed.size()
  let rect = CGRect(
    x: badgeRect.midX - textSize.width / 2,
    y: badgeRect.midY - textSize.height / 2 + badgeRect.height * (badge == .apple ? -0.02 : -0.03),
    width: textSize.width,
    height: textSize.height)
  attributed.draw(in: rect)
}

func writePNG(image: NSImage, to outputURL: URL) throws {
  guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
  else {
    throw IconGeneratorError.couldNotEncodePNG(outputURL.path)
  }
  try png.write(to: outputURL)
}

func writeICNS(baseImage: NSImage, badge: BadgeKind, to outputURL: URL) throws {
  let temporaryRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  let iconsetURL = temporaryRoot.appendingPathComponent("AppIcon.iconset", isDirectory: true)

  try FileManager.default.createDirectory(
    at: iconsetURL,
    withIntermediateDirectories: true,
    attributes: nil)
  defer {
    try? FileManager.default.removeItem(at: temporaryRoot)
  }

  let iconsetFiles: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
  ]

  for (fileName, pixelSize) in iconsetFiles {
    let image = renderIcon(baseImage: baseImage, pixelSize: pixelSize, badge: badge)
    try writePNG(image: image, to: iconsetURL.appendingPathComponent(fileName, isDirectory: false))
  }

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
  process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
  try process.run()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw IconGeneratorError.iconutilFailed(process.terminationStatus)
  }
}
