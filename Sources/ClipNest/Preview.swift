import AppKit
import SwiftUI
import ClipNestCore

struct FullTextView: NSViewRepresentable {
    let text: String
    let fontSize: Double
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = NSTextView()
        editor.isEditable = false
        editor.isSelectable = true
        editor.drawsBackground = false
        editor.isRichText = false
        editor.textContainerInset = NSSize(width: 16, height: 16)
        editor.autoresizingMask = [.width]
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.textContainer?.widthTracksTextView = true
        editor.setAccessibilityLabel("Full clipboard text")
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text { editor.string = text }
        editor.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        editor.textColor = .labelColor
    }
}

final class PreviewState: ObservableObject {
    @Published var formatted = false
    @Published var image: NSImage?
    @Published var imageError = false
    @Published var zoom = 1.0
}

struct PreviewView: View {
    let entry: Entry
    @ObservedObject var model: Model
    let close: () -> Void
    private let formattedJSON: String?
    @StateObject private var state = PreviewState()
    init(entry: Entry, model: Model, close: @escaping () -> Void) {
        self.entry = entry; self.model = model; self.close = close
        formattedJSON = entry.text.flatMap(JSONFormatter.format)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.text == nil ? "Image preview" : "Full text preview").font(.title3.bold())
                    ItemContext(entry: entry)
                }
                Spacer()
                if formattedJSON != nil { Toggle("Format JSON", isOn: $state.formatted).toggleStyle(.switch) }
                Button("Close", action: close).keyboardShortcut(.cancelAction)
            }
            Divider()
            if let text = entry.text {
                FullTextView(text: state.formatted ? (formattedJSON ?? text) : text, fontSize: model.preferences.textSize)
            } else {
                if let image = state.image {
                    GeometryReader { geometry in
                        let aspect = image.size.width / max(1, image.size.height)
                        let fittedWidth = max(1, min(geometry.size.width - 32, (geometry.size.height - 32) * aspect))
                        ScrollView([.horizontal, .vertical]) {
                            Image(nsImage: image).resizable().interpolation(.high)
                                .frame(width: fittedWidth * state.zoom,
                                       height: fittedWidth * state.zoom / max(0.001, aspect))
                                .padding(16)
                                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                                .background(Checkerboard())
                        }
                    }
                    HStack {
                        Text("\(entry.width) × \(entry.height) px").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("Zoom")
                        Slider(value: $state.zoom, in: 0.25...3).frame(width: 140)
                        Button("Fit") { state.zoom = 1 }
                    }
                } else if state.imageError {
                    VStack { Image(systemName: "exclamationmark.triangle"); Text("Could not load the original image.") }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                if !entry.note.isEmpty { Text(entry.note).textSelection(.enabled).lineLimit(3) }
            }
            Divider()
            HStack {
                Button("Copy") { model.copyAction?(entry, nil) }
                if entry.text != nil {
                    Button("Paste as Plain Text") { model.plainTextPasteAction?(entry) }
                    Button { model.pasteAction?(entry) } label: {
                        Text("Paste to \(model.pasteDestination)").lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: 220)
                    }.help("Paste to \(model.pasteDestination)")
                }
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(entry.bytes), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
            }.disabled(model.copyInFlight || model.dragging)
        }.padding(20).frame(minWidth: 560, minHeight: 420)
            .background(model.preferences.theme == "Black" ? Color.black : Color(nsColor: .windowBackgroundColor))
            .preferredColorScheme(model.preferences.colorScheme)
            .task(id: entry.id) {
                guard entry.text == nil else { return }
                let files = entry.images.map { model.store.imageURL($0.file) }
                let loaded: NSImage? = await withCheckedContinuation { continuation in
                    model.io.async {
                        continuation.resume(returning: files.lazy.compactMap { NSImage(contentsOf: $0) }.first)
                    }
                }
                guard !Task.isCancelled else { return }
                state.image = loaded; state.imageError = loaded == nil
            }
    }
}
