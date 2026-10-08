import AppKit
import SwiftUI
import ServiceManagement
import Carbon

struct Preferences: Codable, Equatable {
    var theme = "Dark"
    private var savedCompactCards: Bool?
    private var savedTextSize: Double?
    private var savedOpacity: Double?
    var compactCards: Bool {
        get { savedCompactCards ?? true }
        set { savedCompactCards = newValue }
    }
    var textSize: Double {
        get { min(16, max(11, savedTextSize ?? 13)) }
        set { savedTextSize = newValue }
    }
    var panelOpacity: Double {
        get { min(1, max(0.3, savedOpacity ?? 0.66)) }
        set { savedOpacity = newValue }
    }
    var hoverEnabled = true
    var hoverDelay = 0.0
    var closeDelay = 0.5
    var historyCount = 100
    var storageMiB = 200
    var shortcutKey = "Space"
    var shortcutModifiers = "Control + Option"
    static let keys: [(String, UInt32)] = [("Space", UInt32(kVK_Space)), ("C", UInt32(kVK_ANSI_C)), ("V", UInt32(kVK_ANSI_V)), ("H", UInt32(kVK_ANSI_H)), ("J", UInt32(kVK_ANSI_J)), ("K", UInt32(kVK_ANSI_K))]
    var keyCode: UInt32 { Self.keys.first { $0.0 == shortcutKey }?.1 ?? UInt32(kVK_Space) }
    var modifiers: UInt32 {
        switch shortcutModifiers {
        case "Command + Shift": return UInt32(cmdKey | shiftKey)
        case "Control + Shift": return UInt32(controlKey | shiftKey)
        case "Command + Option": return UInt32(cmdKey | optionKey)
        default: return UInt32(controlKey | optionKey)
        }
    }
    var shortcutLabel: String { "\(shortcutModifiers) + \(shortcutKey)" }
    var colorScheme: ColorScheme? { theme == "System" ? nil : (theme == "Light" ? .light : .dark) }
    var background: Color { ["Dark", "Black"].contains(theme) ? .black : Color(nsColor: .windowBackgroundColor) }
}

final class LoginState: ObservableObject {
    @Published var enabled = false
    @Published var message = ""
}
struct SettingsView: View {
    @ObservedObject var model: Model
    let retryShortcut: () -> Void
    @StateObject private var login = LoginState()
    private var bundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "slider.horizontal.3").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Make ClipNest yours").font(.title2.bold())
                    Text("Changes are saved automatically.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Form {
                Section("General") {
                    Toggle("Launch at login", isOn: Binding(get: { login.enabled }, set: setLogin))
                        .disabled(!bundled)
                    if !bundled { Text("Open ClipNest.app to enable launch at login.").font(.caption).foregroundStyle(.secondary) }
                    if !login.message.isEmpty { Text(login.message).font(.caption).foregroundStyle(.secondary) }
                    if SMAppService.mainApp.status == .requiresApproval {
                        Button("Open Login Items settings") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    Picker("Appearance", selection: $model.preferences.theme) {
                        ForEach(["System", "Dark", "Light", "Black"], id: \.self) { Text($0) }
                    }
                }
                Section("Display") {
                    Toggle("Compact cards", isOn: $model.preferences.compactCards)
                    HStack {
                        Text("Text size")
                        Slider(value: $model.preferences.textSize, in: 11...16, step: 1)
                        Text("\(Int(model.preferences.textSize)) pt").monospacedDigit().frame(width: 44)
                    }
                    HStack {
                        Text("Background opacity")
                        Slider(value: $model.preferences.panelOpacity, in: 0.3...1, step: 0.05)
                            .disabled(model.preferences.theme == "Black")
                        Text(model.preferences.theme == "Black" ? "100%" : "\(Int((model.preferences.panelOpacity * 100).rounded()))%")
                            .monospacedDigit().frame(width: 44)
                    }
                    Text("Black always uses a solid background. Reduce Transparency also uses a solid background.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Open history") {
                    HStack {
                        Picker("Shortcut", selection: $model.preferences.shortcutModifiers) {
                            ForEach(["Control + Option", "Command + Shift", "Control + Shift", "Command + Option"], id: \.self) { Text($0) }
                        }
                        Picker("Key", selection: $model.preferences.shortcutKey) {
                            ForEach(Preferences.keys.map(\.0), id: \.self) { Text($0) }
                        }.frame(width: 115)
                    }
                    HStack {
                        Text(model.shortcutStatus).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Retry", action: retryShortcut)
                    }
                    Toggle("Open when hovering at the top of the screen", isOn: $model.preferences.hoverEnabled)
                    HStack {
                        Text("Open delay")
                        Slider(value: $model.preferences.hoverDelay, in: 0...1, step: 0.05).disabled(!model.preferences.hoverEnabled)
                        Text(model.preferences.hoverDelay.formatted(.number.precision(.fractionLength(2))) + " s").monospacedDigit().frame(width: 52)
                    }
                    HStack {
                        Text("Close delay")
                        Slider(value: $model.preferences.closeDelay, in: 0.2...1.5, step: 0.05)
                        Text(model.preferences.closeDelay.formatted(.number.precision(.fractionLength(2))) + " s").monospacedDigit().frame(width: 52)
                    }
                }
                Section("History") {
                    Picker("Unpinned items", selection: $model.preferences.historyCount) {
                        ForEach([50, 100, 250, 500], id: \.self) { Text("\($0) items") }
                    }
                    Picker("Storage limit", selection: $model.preferences.storageMiB) {
                        ForEach([100, 200, 500, 1024], id: \.self) { Text("\($0) MiB") }
                    }
                    Text("Lowering a limit removes the oldest unpinned items. Pinned items are kept. New items cannot be saved if pins fill the storage limit.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Per item: text up to 1 MiB · images up to 20 MiB / 40 MP").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            Text("Stored locally · Paste to your active app on click.").font(.caption).foregroundStyle(.secondary)
            Text(model.store.root.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
        }.padding(20).frame(width: 560, height: 640)
            .background(model.preferences.background)
            .preferredColorScheme(model.preferences.colorScheme)
            .onAppear(perform: refreshLogin)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshLogin() }
    }
    private func refreshLogin() {
        guard bundled else { return }
        let status = SMAppService.mainApp.status
        login.enabled = status == .enabled || status == .requiresApproval
        login.message = status == .requiresApproval ? "Allow ClipNest in macOS Login Items to finish setup." : ""
    }
    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLogin()
        } catch { refreshLogin(); login.message = "Could not update launch at login: \(error.localizedDescription)" }
    }
}
