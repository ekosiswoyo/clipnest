import AppKit
import SwiftUI
import ClipNestCore

struct ItemContext: View {
    let entry: Entry
    @StateObject private var state = ThumbnailState()
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    var body: some View {
        HStack(spacing: 5) {
            if let icon = state.image { Image(nsImage: icon).resizable().frame(width: 14, height: 14) }
            else { Image(systemName: "app.dashed").frame(width: 14, height: 14) }
            Text(entry.sourceApp?.name ?? "Unknown app").lineLimit(1)
            Text("·")
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(context.date.timeIntervalSince(entry.date) < 60 ? "Just now" : Self.formatter.localizedString(for: entry.date, relativeTo: context.date))
            }
        }.font(.caption2).foregroundStyle(.secondary)
            .help("Copied on " + entry.date.formatted(date: .abbreviated, time: .standard))
            .task(id: entry.sourceApp?.bundleID) {
                state.image = nil
                if let id = entry.sourceApp?.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    state.image = NSWorkspace.shared.icon(forFile: url.path)
                }
            }
    }
}

struct HistoryEmptyState: View {
    @ObservedObject var model: Model
    var searching: Bool { !model.query.isEmpty || model.filter != .all }
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: searching ? "magnifyingglass" : (model.paused ? "pause.circle" : "doc.on.clipboard"))
                .font(.system(size: 36, weight: .light)).foregroundStyle(.secondary)
            Text(searching ? "No matches found" : (model.paused ? "Recording is paused" : "Your next copy starts here"))
                .font(.headline)
            Text(searching ? "Try another keyword or choose a different filter." : (model.paused ? "Resume recording to save text and images you copy." : "Copy text, a link, or an image in any app.\nIt will appear here, ready to use again."))
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if searching { Button("Show all history") { model.query = ""; model.filter = .all } }
            else if model.paused { Button("Resume recording") { model.togglePause() } }
            else { Text("Open anytime with " + model.preferences.shortcutLabel).font(.caption).foregroundStyle(.secondary) }
        }.padding(24).frame(maxWidth: .infinity, minHeight: 180)
    }
}
