import AppKit
import SwiftUI
import ClipNestCore

/// A dedicated grip keeps dragging separate from the card's click-to-paste action.
struct DragHandle: NSViewRepresentable {
    let entry: Entry
    let model: Model

    func makeNSView(context: Context) -> ClipboardDragView { ClipboardDragView() }
    func updateNSView(_ view: ClipboardDragView, context: Context) {
        view.entry = entry
        view.model = model
    }
}

final class ClipboardDragView: NSView, NSDraggingSource {
    var entry: Entry?
    weak var model: Model?
    private var downEvent: NSEvent?

    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "Drag text or image into another app"
        setAccessibilityLabel("Drag clipboard item into another app")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        let image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor]))
        image?.draw(in: NSRect(x: bounds.midX - 7, y: bounds.midY - 7, width: 14, height: 14))
    }
    override func mouseDown(with event: NSEvent) { downEvent = event }
    override func mouseUp(with event: NSEvent) { downEvent = nil }
    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent, let entry, let model, !model.copyInFlight, !model.dragging else { return }
        guard hypot(event.locationInWindow.x - down.locationInWindow.x,
                    event.locationInWindow.y - down.locationInWindow.y) >= 4 else { return }
        downEvent = nil
        do {
            // Serialize access with history writes. Only load full representations at drag start.
            let payload = try model.io.sync { try ClipboardCodec.item(entry: entry, store: model.store) }
            let item = NSDraggingItem(pasteboardWriter: payload)
            let preview = NSImage(systemSymbolName: entry.text == nil ? "photo" : "doc.text", accessibilityDescription: nil)!
            item.setDraggingFrame(NSRect(x: bounds.midX - 16, y: bounds.midY - 16, width: 32, height: 32), contents: preview)
            model.selected = entry.id
            model.dragging = true
            model.status = "Drop into another app · Esc to cancel"
            let session = beginDraggingSession(with: [item], event: down, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
        } catch {
            model.status = "Drag failed: \(error.localizedDescription)"
        }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        model?.dragging = false
        model?.dragEnded?(operation.contains(.copy))
    }
}
