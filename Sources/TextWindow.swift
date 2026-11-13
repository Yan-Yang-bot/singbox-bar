import Cocoa

final class TextWindow {
    let window: NSWindow
    let textView = NSTextView()
    init(title: String) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 540),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        textView.isEditable = false
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.widthTracksTextView = true
        textView.frame = scroll.contentView.bounds
        scroll.documentView = textView
        window.contentView?.addSubview(scroll)
        window.center()
    }
    func update(_ text: String, highlightErrors: Bool = false) {
        guard textView.string != text else { return }
        let wasAtBottom = textView.visibleRect.maxY >= textView.bounds.maxY - 24
        let value = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ])
        if highlightErrors {
            let source = text as NSString
            source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: .byLines) { line, range, _, _ in
                if line?.range(of: "error", options: .caseInsensitive) != nil {
                    value.addAttribute(.foregroundColor, value: NSColor.systemRed, range: range)
                }
            }
        }
        textView.textStorage?.setAttributedString(value)
        if wasAtBottom { textView.scrollToEndOfDocument(nil) }
    }
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
