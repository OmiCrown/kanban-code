import SwiftUI

/// Compact command editor for launch dialogs.
///
/// Return confirms the dialog. Command+Return inserts a newline in the command.
/// Escape runs `onEscape`, because the text view takes the key before the
/// responder chain reaches the dialog buttons.
struct CommandTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onEscape: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = CommandNSTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onEscape = onEscape
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CommandNSTextView else { return }
        textView.onSubmit = onSubmit
        textView.onEscape = onEscape
        if textView.string != text {
            textView.string = text
        }
    }

    /// The editor is as tall as the command it holds, between one line of
    /// room and `maxHeight`: a scroll view has no height of its own, so it
    /// stayed at the dialog's minimum and hid the end of a long command (the
    /// branch name after `--worktree`) behind a scroller.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let textView = nsView.documentView as? NSTextView else { return nil }
        let width = proposal.width ?? 400
        let inset = textView.textContainerInset
        let padding = textView.textContainer?.lineFragmentPadding ?? 5
        let textWidth = max(width - 2 * inset.width - 2 * padding, 40)
        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let measured = NSAttributedString(string: text.isEmpty ? " " : text, attributes: [.font: font])
            .boundingRect(
                with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
        let height = ceil(measured.height) + 2 * inset.height + font.pointSize
        return CGSize(width: width, height: min(max(height, Self.minHeight), Self.maxHeight))
    }

    static let minHeight: CGFloat = 36
    static let maxHeight: CGFloat = 120

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CommandTextEditor

        init(_ parent: CommandTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

final class CommandNSTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onEscape: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn && modifiers == .command {
            insertNewlineIgnoringFieldEditor(self)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53, let onEscape {
            onEscape()
            return
        }
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn && modifiers.isEmpty {
            onSubmit?()
            return
        }
        if isReturn && modifiers == .command {
            insertNewlineIgnoringFieldEditor(self)
            return
        }
        super.keyDown(with: event)
    }
}
