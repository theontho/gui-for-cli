import Foundation

enum BundleIconEmojiMap {
  private static let values: [String: String] = [
    "point.3.connected.trianglepath.dotted": "🧬",
    "doc.text": "📄",
    "doc.text.magnifyingglass": "🔎",
    "text.page": "📄",
    "text.page.badge.magnifyingglass": "🔎",
    "text.badge.checkmark": "✅",
    "doc.badge.gearshape": "⚙️",
    "stethoscope": "🩺",
    "waveform.path.ecg": "〰️",
    "waveform.path.ecg.rectangle": "🩺",
    "person.2.wave.2": "👥",
    "person.3.sequence": "👨‍👩‍👧",
    "pawprint": "🐾",
    "tree": "🌳",
    "books.vertical": "📚",
    "folder": "📁",
    "folder.badge.gearshape": "🗂️",
    "externaldrive": "💽",
    "externaldrive.connected.to.line.below": "💽",
    "tray.and.arrow.down": "📥",
    "terminal": "▸",
    "scissors": "✂️",
    "hammer": "🔨",
    "square.grid.3x3": "▦",
    "tablecells": "▦",
    "arrow.down.circle": "⬇️",
    "arrow.clockwise": "🔄",
    "arrow.clockwise.circle": "🔄",
    "arrow.triangle.2.circlepath": "🔁",
    "arrow.triangle.merge": "🔀",
    "checklist": "☑️",
    "checkmark.circle.fill": "✅",
    "checkmark.seal": "✓",
    "number.circle": "#",
    "trash": "🗑️",
    "trash.fill": "🗑️",
    "gearshape": "⚙️",
    "globe": "🌐",
    "play": "▶",
    "play.fill": "▶",
    "rectangle.3.group": "▦",
    "exclamationmark.triangle.fill": "⚠️",
  ]

  static func emoji(iconName: String?, explicit: String?, fallbackSystemImage: String) -> String {
    if let explicit = explicit.nonEmpty {
      return explicit
    }
    let name = iconName.nonEmpty ?? fallbackSystemImage
    return values[name] ?? values[fallbackSystemImage] ?? "•"
  }
}
