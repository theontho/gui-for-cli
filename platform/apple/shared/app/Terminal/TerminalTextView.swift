import SwiftUI

#if os(macOS)
  import AppKit
  private typealias PlatformTextFont = NSFont
  private let terminalTextColor = NSColor.labelColor
#else
  import UIKit
  private typealias PlatformTextFont = UIFont
  private let terminalTextColor = UIColor.label
#endif

/// Read-only, selectable terminal output backed by a native text view.
/// Follows the end of the output while the view is scrolled to the bottom.
struct TerminalTextView {
  let buffer: TerminalOutputBuffer
  let textDirection: LayoutDirection
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  func makeCoordinator() -> TerminalTextSync { TerminalTextSync() }

  private var style: TerminalTextStyle {
    #if os(macOS)
      let base: CGFloat = 12
    #else
      let base: CGFloat = 15
    #endif
    return TerminalTextStyle(
      fontSize: (base * dynamicTypeSize.terminalScale).rounded(), textDirection: textDirection)
  }
}

struct TerminalTextStyle: Equatable {
  var fontSize: CGFloat
  var textDirection: LayoutDirection

  var attributes: [NSAttributedString.Key: Any] {
    let paragraph = NSMutableParagraphStyle()
    paragraph.baseWritingDirection = textDirection == .rightToLeft ? .rightToLeft : .leftToRight
    paragraph.alignment = textDirection == .rightToLeft ? .right : .left
    return [
      .font: PlatformTextFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
      .foregroundColor: terminalTextColor,
      .paragraphStyle: paragraph,
    ]
  }
}

/// Keeps a text storage in step with a `TerminalOutputBuffer`: only lines
/// appended since the last sync are inserted; the text is rebuilt when the
/// buffer is trimmed, the buffer (tab) changes, or the style changes.
@MainActor
final class TerminalTextSync {
  private var bufferID: ObjectIdentifier?
  private var generation = -1
  private var appendedLineCount = 0
  private var style: TerminalTextStyle?

  /// Returns whether the text was rebuilt rather than appended to.
  @discardableResult
  func apply(_ buffer: TerminalOutputBuffer, style: TerminalTextStyle, to storage: NSTextStorage)
    -> Bool
  {
    let needsRebuild =
      bufferID != ObjectIdentifier(buffer) || generation != buffer.generation
      || self.style != style
    let previousCount = appendedLineCount
    bufferID = ObjectIdentifier(buffer)
    generation = buffer.generation
    appendedLineCount = buffer.appendedLineCount
    self.style = style
    if needsRebuild {
      storage.setAttributedString(
        NSAttributedString(string: buffer.text, attributes: style.attributes))
      return true
    }
    let newLines = buffer.lines(appendedAfter: previousCount)
    guard !newLines.isEmpty else { return false }
    let separator = previousCount > 0 ? "\n" : ""
    storage.append(
      NSAttributedString(
        string: separator + newLines.joined(separator: "\n"), attributes: style.attributes))
    return false
  }
}

#if os(macOS)
  extension TerminalTextView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
      let scrollView = NSTextView.scrollableTextView()
      scrollView.drawsBackground = false
      scrollView.hasHorizontalScroller = false
      if let textView = scrollView.documentView as? NSTextView {
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 8, height: 10)
      }
      return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
      guard let textView = scrollView.documentView as? NSTextView,
        let storage = textView.textStorage
      else { return }
      let visible = scrollView.contentView.bounds
      let followsEnd = visible.maxY >= textView.frame.height - 4
      storage.beginEditing()
      let rebuilt = context.coordinator.apply(buffer, style: style, to: storage)
      storage.endEditing()
      if followsEnd || rebuilt {
        textView.scrollToEndOfDocument(nil)
      }
    }
  }
#else
  extension TerminalTextView: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextView {
      let textView = UITextView()
      textView.isEditable = false
      textView.isSelectable = true
      textView.backgroundColor = .clear
      textView.alwaysBounceVertical = true
      textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
      return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
      let followsEnd =
        textView.contentOffset.y + textView.bounds.height >= textView.contentSize.height - 4
      let storage = textView.textStorage
      storage.beginEditing()
      let rebuilt = context.coordinator.apply(buffer, style: style, to: storage)
      storage.endEditing()
      if followsEnd || rebuilt {
        textView.scrollRangeToVisible(NSRange(location: storage.length, length: 0))
      }
    }
  }
#endif

extension DynamicTypeSize {
  /// Text scale relative to `.large`, matching the app's text-size commands.
  fileprivate var terminalScale: CGFloat {
    switch self {
    case .xSmall: 0.82
    case .small: 0.88
    case .medium: 0.94
    case .large: 1
    case .xLarge: 1.12
    case .xxLarge: 1.24
    case .xxxLarge: 1.36
    case .accessibility1: 1.6
    default: 1.9
    }
  }
}
