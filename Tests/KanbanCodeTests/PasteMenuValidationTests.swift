import AppKit
import Testing
@testable import KanbanCode

/// A plain-text view enables Paste only for text on the clipboard, so with a
/// screenshot there the menu item was greyed out, in the context menu and in
/// the Edit menu, though the editor does take the image.
@Suite("Paste menu item with an image on the clipboard", .serialized)
@MainActor
struct PasteMenuValidationTests {
    /// The whole clipboard, so a test leaves the user's copy as it found it.
    private func saveClipboard() -> [[(NSPasteboard.PasteboardType, Data)]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    private func restoreClipboard(_ saved: [[(NSPasteboard.PasteboardType, Data)]]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items = saved.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    private func pngData() throws -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4))
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    private enum Clipboard { case png, tiff, jpeg, text, empty }

    /// Whether the editor offers Paste, through both the validation calls a menu may use.
    private func pasteEnabled(clipboard: Clipboard, takesImages: Bool) throws -> (userInterface: Bool, menu: Bool) {
        let saved = saveClipboard()
        defer { restoreClipboard(saved) }

        let editor = SubmitTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        if takesImages { editor.onImagePaste = { _ in "[Image #1]" } }

        let png = try pngData()
        let tiff = try #require(NSImage(data: png)?.tiffRepresentation)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch clipboard {
        case .png: pasteboard.setData(png, forType: .png)
        case .tiff: pasteboard.setData(tiff, forType: .tiff)
        case .jpeg:
            let jpeg = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [:]))
            pasteboard.setData(jpeg, forType: NSPasteboard.PasteboardType("public.jpeg"))
        case .text: pasteboard.setString("hello", forType: .string)
        case .empty: break
        }

        let item = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")
        let menu = (editor as NSMenuItemValidation).validateMenuItem(item)
        return (editor.validateUserInterfaceItem(item), menu)
    }

    @Test("Paste is enabled for a PNG, a TIFF or a JPEG, which is what a screenshot is")
    func imageClipboardEnablesPaste() throws {
        for clipboard in [Clipboard.png, .tiff, .jpeg] {
            let enabled = try pasteEnabled(clipboard: clipboard, takesImages: true)
            #expect(enabled.userInterface, "validateUserInterfaceItem, \(clipboard)")
            #expect(enabled.menu, "validateMenuItem, \(clipboard)")
        }
    }

    @Test("Paste stays enabled for text")
    func textClipboardEnablesPaste() throws {
        let enabled = try pasteEnabled(clipboard: .text, takesImages: true)
        #expect(enabled.userInterface)
        #expect(enabled.menu)
    }

    @Test("Paste stays disabled when nothing is on the clipboard")
    func emptyClipboardDisablesPaste() throws {
        let enabled = try pasteEnabled(clipboard: .empty, takesImages: true)
        #expect(!enabled.userInterface)
        #expect(!enabled.menu)
    }

    @Test("Paste stays disabled for an image in an editor that does not take images")
    func editorWithoutImagesDisablesPaste() throws {
        let enabled = try pasteEnabled(clipboard: .png, takesImages: false)
        #expect(!enabled.userInterface)
        #expect(!enabled.menu)
    }
}
