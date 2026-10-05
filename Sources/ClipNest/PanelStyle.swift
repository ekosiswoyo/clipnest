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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                FrostedSurface()
                (scheme == .dark ? Color(red: 0.08, green: 0.09, blue: 0.12) : .white).opacity(scheme == .dark ? 0.66 : 0.72)
            }
            LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.045 : 0.28), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
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
            TextField("Search text, notes, or apps", text: $model.query, onEditingChanged: { editing in interaction.focused = editing })
                .textFieldStyle(.plain).font(.system(size: 13))
                .accessibilityLabel("Search clipboard history")
                .onTapGesture { focus() }
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
    @ObservedObject var model: Model
    @StateObject private var interaction = InteractionState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    private var copied: Bool { model.copiedID == entry.id }
    private var selected: Bool { model.selected == entry.id }
    private var showActions: Bool { interaction.hovered || selected }
    private var code: Bool { ["Code / Text", "JSON", "SQL", "Command"].contains(entry.label) }
    private var tint: Color { copied ? .green : .blue }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { model.copyAction?(entry, nil) } label: {
                HStack(alignment: .top, spacing: 14) {
                    if entry.text == nil, let rep = entry.images.first { Thumbnail(url: model.store.imageURL(rep.file)) }
                    VStack(alignment: .leading, spacing: 8) {
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
                                .font(.system(size: 13, weight: .regular, design: code ? .monospaced : .default))
                                .foregroundStyle(entry.label == "URL" ? Color.blue : Color.primary)
                                .lineSpacing(3).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(entry.note.isEmpty ? "Image" : entry.note).font(.system(size: 13, weight: .medium)).lineLimit(2)
                            Text("\(entry.width) × \(entry.height) px").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        ItemContext(entry: entry)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(QuietButtonStyle()).accessibilityLabel("Copy \(entry.label)")
            VStack(spacing: 1) {
                CardAction(symbol: "doc.on.doc", title: "Copy") { model.copyAction?(entry, nil) }
                CardAction(symbol: entry.pinned ? "pin.slash" : "pin", title: entry.pinned ? "Unpin" : "Pin") { model.mutate { $0.pin(entry.id) } }
                CardAction(symbol: "trash", title: "Delete", destructive: true) { model.mutate { $0.delete(entry.id) } }
            }.opacity(showActions ? 1 : 0)
                .allowsHitTesting(showActions).accessibilityHidden(!showActions)
        }.padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(copied || selected ? tint.opacity(scheme == .dark ? 0.12 : 0.07) : Color.primary.opacity(interaction.hovered ? 0.065 : 0.035)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(copied || selected ? tint.opacity(0.35) : Color.primary.opacity(interaction.hovered ? 0.12 : 0.055), lineWidth: 1))
            .shadow(color: .black.opacity(interaction.hovered ? 0.06 : 0), radius: 5, y: 2)
            .scaleEffect(interaction.hovered && !reduceMotion ? 1.004 : 1)
            .onHover { interaction.hovered = $0 }
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
