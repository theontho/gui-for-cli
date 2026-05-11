import AppKit

@MainActor
enum AppKitViewFactory {
  static func titleLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular)
    -> NSTextField
  {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .systemFont(ofSize: size, weight: weight)
    label.isSelectable = false
    return label
  }

  static func secondaryLabel(_ text: String, size: CGFloat = NSFont.systemFontSize) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.textColor = .secondaryLabelColor
    label.font = .systemFont(ofSize: size)
    label.isSelectable = false
    return label
  }

  static func verticalStack(
    spacing: CGFloat = 12,
    alignment: NSLayoutConstraint.Attribute = .leading
  ) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = alignment
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }

  static func horizontalStack(spacing: CGFloat = 8) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.distribution = .fill
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }

  static func scrollDocument(containing documentView: NSView) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    let container = AppKitDocumentView()
    container.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(documentView)
    scrollView.documentView = container
    NSLayoutConstraint.activate([
      documentView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
      documentView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
      documentView.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
      documentView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
      container.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
    ])
    return scrollView
  }

  static func boxed(title: String?, content: NSView) -> NSBox {
    let box = NSBox()
    box.title = title ?? ""
    box.boxType = .primary
    box.contentViewMargins = NSSize(width: 16, height: 16)
    box.translatesAutoresizingMaskIntoConstraints = false
    guard let container = box.contentView else { return box }
    container.addSubview(content)
    content.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      content.topAnchor.constraint(equalTo: container.topAnchor),
      content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    return box
  }
}

final class AppKitDocumentView: NSView {
  override var isFlipped: Bool {
    true
  }
}
