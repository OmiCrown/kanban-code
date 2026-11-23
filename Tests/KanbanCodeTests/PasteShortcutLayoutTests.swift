import AppKit
import Testing
@testable import KanbanCode

/// Cmd+V is the same key in every layout. With a Russian layout the key types
/// "м", so a check for the character "v" never saw the paste, and an image on
/// the clipboard did not go into the prompt.
@Suite("Paste shortcut in other keyboard layouts", .serialized)
@MainActor
struct PasteShortcutLayoutTests {
    private let vKeyCode: UInt16 = 9

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

    /// A prompt editor that is the first responder, with an image on the clipboard.
    /// Returns what Cmd+<key> did: whether the key was taken and the images pasted.
    private func press(characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = .command) throws -> (handled: Bool, images: Int, text: String) {
        let saved = saveClipboard()
        defer { restoreClipboard(saved) }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let content = NSView(frame: window.contentLayoutRect)
        window.contentView = content
        let editor = SubmitTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        content.addSubview(editor)
        var images = 0
        editor.onImagePaste = { _ in images += 1; return "[Image #\(images)]" }
        #expect(window.makeFirstResponder(editor))

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(try pngData(), forType: .png)

        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
        let handled = content.performKeyEquivalent(with: event)
        return (handled, images, editor.string)
    }

    @Test("Cmd+V pastes the image with a Latin layout")
    func latinLayout() throws {
        let result = try press(characters: "v", keyCode: vKeyCode)
        #expect(result.handled)
        #expect(result.images == 1)
        #expect(result.text == "[Image #1]")
    }

    @Test("Cmd+V pastes the image with a Russian layout, where the key types м")
    func russianLayout() throws {
        let result = try press(characters: "м", keyCode: vKeyCode)
        #expect(result.handled)
        #expect(result.images == 1)
        #expect(result.text == "[Image #1]")
    }

    @Test("a key that types a Latin letter other than v is not a paste, even on the V key's position")
    func dvorakKeyAtVPosition() throws {
        // On a Dvorak layout the key at the position of V types ".".
        let result = try press(characters: ".", keyCode: vKeyCode)
        #expect(!result.handled)
        #expect(result.images == 0)
    }

    @Test("Cmd+Shift+V in a Russian layout is not taken")
    func shiftedPasteIsNotTaken() throws {
        let result = try press(characters: "м", keyCode: vKeyCode, modifiers: [.command, .shift])
        #expect(!result.handled)
        #expect(result.images == 0)
    }
}
