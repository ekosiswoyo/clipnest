import AppKit
import SwiftUI
import ClipNestCore

final class InteractionState: ObservableObject {
    @Published var hovered = false
    @Published var focused = false
}

struct FrostedSurface: NSViewRepresentable {
    @Environment(\.colorScheme) private var scheme
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    }
}

struct PanelSurface: View {
    var theme: String
    var opacity: Double
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if theme == "Black" {
                Color.black
            } else if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                FrostedSurface()
                (scheme == .dark ? Color(red: 0.08, green: 0.09, blue: 0.12) : .white).opacity(opacity)
            }
            if theme != "Black" {
                LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.045 : 0.28), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(.easeOut(duration: reduceMotion ? 0 : 0.12), value: configuration.isPressed)
    }
}

struct CardAction: View {
    let symbol: String
    let title: String
    var destructive = false
    let action: () -> Void
    @StateObject private var interaction = InteractionState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(destructive && interaction.hovered ? Color.red : Color.secondary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(interaction.hovered ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(QuietButtonStyle())
            .onHover { interaction.hovered = $0 }
            .animation(.easeOut(duration: reduceMotion ? 0 : 0.15), value: interaction.hovered)
            .help(title).accessibilityLabel(title)
    }
}

final class SearchTextField: NSTextField {
    var focusPanel: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        // Hover panels cannot become key until explicitly activated.
        focusPanel?()
        super.mouseDown(with: event)
    }
}

struct SearchInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let focus: () -> Void

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchInput
        init(_ parent: SearchInput) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func controlTextDidBeginEditing(_ notification: Notification) { parent.focused = true }
        func controlTextDidEndEditing(_ notification: Notification) { parent.focused = false }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> SearchTextField {
        let field = SearchTextField(string: text)
        field.placeholderString = "Search text, notes, or apps"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.setAccessibilityLabel("Search clipboard history")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.focusPanel = focus
        return field
    }
    func updateNSView(_ field: SearchTextField, context: Context) {
        context.coordinator.parent = self
        field.focusPanel = focus
        if field.stringValue != text { field.stringValue = text }
    }
}

struct SearchBar: View {
    @ObservedObject var model: Model
    let focus: () -> Void
    @StateObject private var interaction = InteractionState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(interaction.focused ? Color.blue : Color.secondary)
            SearchInput(text: $model.query, focused: $interaction.focused, focus: focus)
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(.secondary)
                }.buttonStyle(QuietButtonStyle()).help("Clear search").accessibilityLabel("Clear search")
                    .transition(.opacity)
            }
        }.padding(.horizontal, 13).frame(height: 40)
            .background(Color.primary.opacity(interaction.focused ? 0.055 : 0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(interaction.focused ? Color.blue.opacity(0.65) : Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: .blue.opacity(interaction.focused ? 0.08 : 0), radius: 4)
            .animation(.easeOut(duration: reduceMotion ? 0 : 0.18), value: interaction.focused)
            .animation(.easeOut(duration: reduceMotion ? 0 : 0.15), value: model.query.isEmpty)
    }
}

struct ClipboardCard: View {
    let entry: Entry
    private let formattedJSON: String?
    @ObservedObject var model: Model
    @StateObject private var interaction = InteractionState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    private var compact: Bool { model.preferences.compactCards }
    private var black: Bool { model.preferences.theme == "Black" }
    private var copied: Bool { model.copiedID == entry.id }
    private var selected: Bool { model.selected == entry.id }
    private var showActions: Bool { interaction.hovered || selected }
    private var code: Bool { ["Code / Text", "JSON", "SQL", "Command"].contains(entry.label) }
    private var tint: Color { copied ? .green : .blue }
    init(entry: Entry, model: Model) {
        self.entry = entry
        self.model = model
        formattedJSON = entry.text.flatMap(JSONFormatter.format)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { model.pasteAction?(entry) } label: {
                HStack(alignment: .top, spacing: 14) {
                    if entry.text == nil, let rep = entry.images.first { Thumbnail(url: model.store.imageURL(rep.file)) }
                    VStack(alignment: .leading, spacing: compact ? 4 : 8) {
                        HStack(spacing: 6) {
                            Text(entry.label.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.8)
                                .foregroundStyle(.secondary)
                            if entry.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(.blue).accessibilityLabel("Pinned") }
                            Spacer(minLength: 4)
                            if copied {
                                Label("Copied", systemImage: "checkmark.circle.fill").font(.system(size: 11, weight: .medium)).foregroundStyle(.green).transition(.opacity)
                            } else {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(entry.bytes), countStyle: .file))
                                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                        }
                        if let text = entry.text {
                            Text(String(text.prefix(600)))
                                .font(.system(size: model.preferences.textSize, weight: .regular, design: code ? .monospaced : .default))
                                .foregroundStyle(entry.label == "URL" ? Color.blue : Color.primary)
                                .lineSpacing(compact ? 1 : 3).lineLimit(compact ? 2 : 3).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(entry.note.isEmpty ? "Image" : entry.note).font(.system(size: model.preferences.textSize, weight: .medium)).lineLimit(compact ? 1 : 2)
                            Text("\(entry.width) × \(entry.height) px").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        ItemContext(entry: entry)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(QuietButtonStyle()).accessibilityLabel("\(entry.text == nil ? "Copy" : "Paste") \(entry.label)")
                .help(entry.text == nil ? "Copy image" : "Paste into the previously active app")
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    CardAction(symbol: "doc.on.doc", title: "Copy") { model.copyAction?(entry, nil) }
                    CardAction(symbol: entry.pinned ? "pin.slash" : "pin", title: entry.pinned ? "Unpin" : "Pin") { model.mutate { $0.pin(entry.id) } }
                }
                HStack(spacing: 0) {
                    DragHandle(entry: entry, model: model).frame(width: 28, height: 24)
                    Menu {
                        if let formatted = formattedJSON {
                            Button("Copy formatted JSON") { model.copyAction?(entry, formatted) }
                        }
                        Button("Delete", role: .destructive) { model.mutate { $0.delete(entry.id) } }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 13)).frame(width: 28, height: 24)
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .help("More actions").accessibilityLabel("More actions")
                }
            }.opacity(showActions ? 1 : 0)
                .allowsHitTesting(showActions).accessibilityHidden(!showActions)
        }.padding(compact ? 10 : 14)
            .background(RoundedRectangle(cornerRadius: 14).fill(copied || selected ? tint.opacity(scheme == .dark ? 0.12 : 0.07) : (black ? Color(white: interaction.hovered ? 0.10 : 0.065) : Color.primary.opacity(interaction.hovered ? 0.065 : 0.035))))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(copied || selected ? tint.opacity(0.35) : Color.primary.opacity(black ? (interaction.hovered ? 0.25 : 0.17) : (interaction.hovered ? 0.12 : 0.055)), lineWidth: 1))
            .shadow(color: .black.opacity(interaction.hovered ? 0.06 : 0), radius: 5, y: 2)
            .scaleEffect(interaction.hovered && !reduceMotion ? 1.004 : 1)
            .onHover { hovering in
                interaction.hovered = hovering
                if hovering && !model.dragging { model.selected = entry.id }
            }
            .animation(.easeOut(duration: reduceMotion ? 0 : 0.16), value: interaction.hovered)
            .animation(.easeOut(duration: reduceMotion ? 0 : 0.18), value: copied)
            .animation(.easeOut(duration: reduceMotion ? 0 : 0.15), value: selected)
    }
}

struct Checkerboard: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            for row in 0..<Int(ceil(size.height / cell)) {
                for column in 0..<Int(ceil(size.width / cell)) {
                    let shade = scheme == .dark ? ((row + column).isMultiple(of: 2) ? 0.20 : 0.26) : ((row + column).isMultiple(of: 2) ? 0.88 : 0.96)
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)), with: .color(Color(white: shade)))
                }
            }
        }.accessibilityHidden(true)
    }
}
