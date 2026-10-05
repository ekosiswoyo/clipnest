import AppKit
import SwiftUI
import Carbon
import ImageIO
import ClipNestCore

final class KeyPanel: NSPanel {
    var wantsFocus = false
    override var canBecomeKey: Bool { wantsFocus }
    var escape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { escape?() }
}
@MainActor final class Model: ObservableObject {
    @Published var entries: [Entry] = []
    @Published var preferences = Preferences() {
        didSet {
            guard preferences != oldValue else { return }
            do { try JSONEncoder().encode(preferences).write(to: store.root.appendingPathComponent("settings.json"), options: .atomic) }
            catch { status = "Could not save settings: \(error.localizedDescription)" }
            onPreferences?(oldValue)
        }
    }
    var onPreferences: ((Preferences) -> Void)?
    var captureSource: (() -> SourceApp?)?
    @Published var copiedID: UUID?
    var copyInFlight = false
    @Published var status = "Ready" { didSet { onStatus?(status) } }
    var onStatus: ((String) -> Void)?
    @Published var panelExpanded = false
    @Published var paused = false
    @Published var query = ""
    @Published var selected: UUID?
    @Published var shortcutStatus = ""
    nonisolated let store: HistoryStore
    let io = DispatchQueue(label: "ClipNest.storage", qos: .utility)
    var save: DispatchWorkItem?
    var count = NSPasteboard.general.changeCount
    var busy = false
    var copyAction: ((Entry, String?) -> Void)?
    init() {
        let root = ProcessInfo.processInfo.environment["CLIPNEST_DATA_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ClipNest")
        do { store = try HistoryStore(root: root); entries = store.entries; if store.needsRecovery { status = StoreError.metadataCorrupt.localizedDescription } }
        catch { fatalError("Unable to open Application Support: \(error.localizedDescription)") }
        if let data = try? Data(contentsOf: store.root.appendingPathComponent("settings.json")), let saved = try? JSONDecoder().decode(Preferences.self, from: data) { preferences = saved }
        store.applyLimits(count: preferences.historyCount, bytes: preferences.storageMiB * 1024 * 1024)
        entries = store.entries
        do { try store.flush() } catch { status = "Could not save history: \(error.localizedDescription)" }
    }
    var filtered: [Entry] { entries.filter { query.isEmpty || ($0.text ?? "").localizedCaseInsensitiveContains(query) || $0.label.localizedCaseInsensitiveContains(query) || $0.note.localizedCaseInsensitiveContains(query) || ($0.sourceApp?.name ?? "").localizedCaseInsensitiveContains(query) } }
    func refresh() {
        io.async { let snapshot = self.store.entries; Task { @MainActor in self.entries = snapshot } }
        save?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do { try self.store.flush() } catch { Task { @MainActor in self.status = error.localizedDescription } }
        }
        save = task; io.asyncAfter(deadline: .now() + 0.35, execute: task)
    }
    func mutate(_ action: @escaping (HistoryStore) -> Void) {
        io.async {
            action(self.store); let recovery = self.store.needsRecovery
            Task { @MainActor in self.status = recovery ? StoreError.metadataCorrupt.localizedDescription : "History updated"; self.refresh() }
        }
    }
    func togglePause() { paused.toggle(); count = NSPasteboard.general.changeCount; status = paused ? "Clipboard recording paused" : "Clipboard recording active" }
    func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != count else { return }
        if paused { count = pb.changeCount; return }
        guard !busy else { return }
        count = pb.changeCount
        let capture: Capture
        do { capture = try ClipboardCodec.capture(pb) } catch { status = error.localizedDescription; return }
        if case .ignored = capture { return }
        busy = true
        let source = captureSource?()
        io.async {
            do { switch capture { case .image(let images): try self.store.addImage(images, sourceApp: source); case .text(let text): try self.store.addText(text, sourceApp: source); case .ignored: break }
                Task { @MainActor in self.busy = false; self.status = "Saved locally"; self.refresh() }
            } catch { Task { @MainActor in self.busy = false; self.status = error.localizedDescription } }
        }
    }
    func move(_ step: Int) {
        let list = filtered; guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == selected } ?? (step > 0 ? -1 : list.count)
        selected = list[min(max(index + step, 0), list.count - 1)].id
    }
}
final class Thumbnails {
    static let shared = Thumbnails()
    let cache = NSCache<NSString, NSImage>()
    let queue = DispatchQueue(label: "ClipNest.thumbnails", qos: .utility)
    init() { cache.totalCostLimit = 16 * 1024 * 1024; cache.countLimit = 64 }
    func load(_ url: URL, completion: @escaping (NSImage?) -> Void) {
        if let image = cache.object(forKey: url.path as NSString) { completion(image); return }
        queue.async {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 240, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { DispatchQueue.main.async { completion(nil) }; return }
            let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            self.cache.setObject(image, forKey: url.path as NSString, cost: cg.bytesPerRow * cg.height)
            DispatchQueue.main.async { completion(image) }
        }
    }
}
final class ThumbnailState: ObservableObject { @Published var image: NSImage? }
struct Thumbnail: View {
    let url: URL
    @StateObject private var state = ThumbnailState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Checkerboard()
            if let image = state.image {
                Image(nsImage: image).resizable().scaledToFit().padding(4).transition(.opacity)
            } else {
                Image(systemName: "photo").font(.system(size: 22, weight: .light)).foregroundStyle(.secondary)
            }
        }.frame(width: 96, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            .animation(.easeOut(duration: reduceMotion ? 0 : 0.2), value: state.image != nil)
            .task(id: url) { Thumbnails.shared.load(url) { state.image = $0 } }
    }
}
struct NotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let shoulder: CGFloat = min(16, rect.height / 2)
        let radius: CGFloat = min(24, max(0, (rect.height - shoulder) / 2))
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.width - shoulder, y: shoulder), control: CGPoint(x: rect.width - shoulder, y: 0))
        path.addLine(to: CGPoint(x: rect.width - shoulder, y: rect.height - radius))
        path.addQuadCurve(to: CGPoint(x: rect.width - shoulder - radius, y: rect.height), control: CGPoint(x: rect.width - shoulder, y: rect.height))
        path.addLine(to: CGPoint(x: shoulder + radius, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: shoulder, y: rect.height - radius), control: CGPoint(x: shoulder, y: rect.height))
        path.addLine(to: CGPoint(x: shoulder, y: shoulder))
        path.addQuadCurve(to: .zero, control: CGPoint(x: shoulder, y: 0))
        path.closeSubpath()
        return path
    }
}
struct HistoryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: Model
    var width: CGFloat = 560
    var topInset: CGFloat = 24
    let focus: () -> Void
    let close: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            HStack { Image(systemName: "square.on.square"); Text("ClipNest").font(.system(size: 16, weight: .semibold)); Spacer(); Text(model.paused ? "Paused" : "\(model.entries.count) items").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4).background(Color.primary.opacity(0.04), in: Capsule()); CardAction(symbol: "xmark", title: "Close history", action: close) }
            SearchBar(model: model, focus: focus)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.filtered) { entry in
                            ClipboardCard(entry: entry, model: model).id(entry.id)
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
                            .contextMenu {
                                Button("Copy") { model.copyAction?(entry, nil) }
                                Button(entry.pinned ? "Unpin" : "Pin") { model.mutate { $0.pin(entry.id) } }
                                if entry.label == "JSON", let text = entry.text {
                                    Button("Copy formatted JSON") { if let object = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed), let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]), let formatted = String(data: data, encoding: .utf8) { model.copyAction?(entry, formatted) } }
                                }
                                if entry.text == nil { Button("Edit note…") { focus(); let alert = NSAlert(); alert.messageText = "Image note"; let field = NSTextField(string: entry.note); field.frame = NSRect(x: 0, y: 0, width: 300, height: 26); alert.accessoryView = field; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel"); if alert.runModal() == .alertFirstButtonReturn { model.mutate { $0.note(entry.id, field.stringValue) } } } }
                                Button("Delete") { model.mutate { $0.delete(entry.id) } }
                            }
                        }
                        if model.filtered.isEmpty { HistoryEmptyState(model: model).transition(.opacity) }
                    }.padding(2)
                        .animation(.easeOut(duration: reduceMotion ? 0 : 0.18), value: model.filtered.map(\.id))
                }.onChange(of: model.selected) { id in if let id { proxy.scrollTo(id) } }
            }
            Divider().opacity(0.4)
            HStack(spacing: 6) {
                if model.copiedID != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                Text(model.status)
            }.font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(24).frame(width: width, height: 470).padding(.top, topInset).background(PanelSurface()).clipShape(NotchShape()).overlay(NotchShape().stroke(Color.primary.opacity(0.09), lineWidth: 1)).preferredColorScheme(model.preferences.colorScheme)
        .scaleEffect(x: model.panelExpanded || reduceMotion ? 1 : 0.92, y: model.panelExpanded || reduceMotion ? 1 : 0.04, anchor: .top)
        .opacity(model.panelExpanded ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : (model.panelExpanded ? .spring(response: 0.40, dampingFraction: 0.86) : .easeInOut(duration: 0.22)), value: model.panelExpanded)
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Model()
    var panel: KeyPanel!
    var item: NSStatusItem!
    var trigger = NSRect.zero
    var open = false
    var transitionID = 0
    var outsideSince: Date?
    var insideSince: Date?
    var feedbackID = 0
    var suppressed = false
    var keyboardLatch = false
    var previousApp: NSRunningApplication?
    var timers: [Timer] = []
    var hotkey: EventHotKeyRef?
    var handler: EventHandlerRef?
    var keyMonitor: Any?
    var settingsWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.level = .statusBar; panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]; panel.escape = { [weak self] in self?.hide() }
        geometry()
        if CommandLine.arguments.contains("--smoke-test") { Task { await self.smoke() } }
        if CommandLine.arguments.contains("--panel-check") { Task { await self.panelCheck() } }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength); item.button?.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "ClipNest")
        model.onStatus = { [weak self] status in
            guard let self else { return }
            let warning = status.hasPrefix("Skipped") || status.contains("full") || status.contains("corrupt") || status.lowercased().contains("failed") || status.contains("missing") || status.contains("Invalid")
            self.item.button?.image = NSImage(systemSymbolName: warning ? "exclamationmark.circle" : "square.on.square", accessibilityDescription: warning ? status : "ClipNest")
            self.item.button?.contentTintColor = warning ? .systemOrange : nil
            self.item.button?.toolTip = status; self.menu()
        }
        model.onStatus?(model.status)
        menu()
        model.copyAction = { [weak self] entry, text in self?.copy(entry, text) }
        model.captureSource = { [weak self] in
            guard let self else { return nil }
            let front = NSWorkspace.shared.frontmostApplication
            let app = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? self.previousApp : front
            guard let app else { return nil }
            return SourceApp(name: app.localizedName ?? "Unknown app", bundleID: app.bundleIdentifier)
        }
        model.onPreferences = { [weak self] old in
            guard let self else { return }
            let preferences = self.model.preferences
            if preferences.shortcutKey != old.shortcutKey || preferences.shortcutModifiers != old.shortcutModifiers { self.registerShortcut(); self.menu() }
            if preferences.historyCount != old.historyCount || preferences.storageMiB != old.storageMiB {
                self.model.mutate { $0.applyLimits(count: preferences.historyCount, bytes: preferences.storageMiB * 1024 * 1024) }
            }
            self.insideSince = nil
        }
        registerShortcut()
        if CommandLine.arguments.contains("--diagnostics") {
            timers.append(Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in MainActor.assumeIsolated { if let self { print("Diagnostic: panelOpen=\(self.open), pointer=\(NSEvent.mouseLocation), trigger=\(self.trigger), shortcut=\(self.model.shortcutStatus)"); fflush(stdout) } } })
        }
        timers.append(Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.model.poll() } })
        timers.append(Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.hover() } })
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            if event.keyCode == 53 { self.hide(); return nil }
            if let editor = self.panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            if event.keyCode == 125 { self.model.move(1); return nil }
            if event.keyCode == 126 { self.model.move(-1); return nil }
            if event.keyCode == 36, let entry = self.model.filtered.first(where: { $0.id == self.model.selected }) ?? self.model.filtered.first { self.copy(entry, nil); return nil }
            return event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(geometry), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleep), name: NSWorkspace.willSleepNotification, object: nil)
    }
    @objc func geometry() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.frame; let inset = screen.safeAreaInsets.top
        let width = min(560, frame.width - 24)
        let bridge = max(inset, 24)
        if open, let host = panel.contentView as? NSHostingView<HistoryView>, host.rootView.width != width || host.rootView.topInset != bridge {
            host.rootView = HistoryView(model: model, width: width, topInset: bridge, focus: { [weak self] in self?.takeFocus() }, close: { [weak self] in self?.hide() })
        }
        panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.maxY - bridge - 470, width: width, height: bridge + 470), display: true)
        let notchWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea { notchWidth = max(100, right.minX - left.maxX) } else { notchWidth = 100 }
        let compactWidth = notchWidth + 32
        trigger = NSRect(x: frame.midX - compactWidth / 2, y: frame.maxY - bridge - 8, width: compactWidth, height: bridge + 8)

    }
    @objc func wake() { model.count = NSPasteboard.general.changeCount; geometry() }
    @objc func sleep() { hide() }
    func hover(point suppliedPoint: NSPoint? = nil, now: Date = Date()) {
        if CommandLine.arguments.contains("--panel-check") { return }
        if NSApp.modalWindow != nil || model.copyInFlight || model.copiedID != nil { return }
        let point = suppliedPoint ?? NSEvent.mouseLocation
        let inside = trigger.contains(point) || (open && panel.frame.contains(point))
        if keyboardLatch { if inside { keyboardLatch = false } else { return } }
        if inside {
            outsideSince = nil
            if suppressed { return }
            if insideSince == nil { insideSince = now }
            if !open && model.preferences.hoverEnabled && now.timeIntervalSince(insideSince!) >= model.preferences.hoverDelay { show(focus: false) }
        } else {
            insideSince = nil; suppressed = false
            if outsideSince == nil { outsideSince = now }
            if open && now.timeIntervalSince(outsideSince!) >= model.preferences.closeDelay { hide() }
        }
    }
    func show(focus: Bool) {
        feedbackID += 1; model.copiedID = nil
        transitionID += 1
        let transition = transitionID
        if open {
            keyboardLatch = focus
            if focus { takeFocus() }
            return
        }
        model.panelExpanded = false
        let screen = NSScreen.screens.first
        panel.contentView = NSHostingView(rootView: HistoryView(model: model, width: min(560, (screen?.frame.width ?? 584) - 24), topInset: max(screen?.safeAreaInsets.top ?? 0, 24), focus: { [weak self] in self?.takeFocus() }, close: { [weak self] in self?.hide() }))
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        geometry(); keyboardLatch = focus; open = true; panel.alphaValue = 1; panel.orderFrontRegardless()
        if focus { takeFocus() }; model.selected = model.filtered.first?.id
        DispatchQueue.main.async { [weak self] in
            guard let self, self.open, self.transitionID == transition else { return }
            self.model.panelExpanded = true
        }
    }
    func takeFocus() { panel.wantsFocus = true; NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }
    func hide() {
        feedbackID += 1; model.copiedID = nil
        guard open else { return }
        transitionID += 1
        let transition = transitionID
        let hadFocus = panel.isKeyWindow
        model.panelExpanded = false
        panel.wantsFocus = false
        if hadFocus { previousApp?.activate(options: [.activateIgnoringOtherApps]) }
        open = false; keyboardLatch = false; suppressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
            guard let self, !self.open, self.transitionID == transition else { return }
            self.panel.orderOut(nil)
            self.panel.contentView = nil
        }
    }
    func copy(_ entry: Entry, _ formatted: String?) {
        guard !model.copyInFlight else { return }
        model.copyInFlight = true
        feedbackID += 1
        let feedback = feedbackID
        let presentation = transitionID
        model.io.async { [self] in
            do {
                let object = try ClipboardCodec.item(entry: entry, store: self.model.store, formatted: formatted)
                Task { @MainActor in
                    let pb = NSPasteboard.general
                    self.model.copyInFlight = false
                    pb.clearContents()
                    if pb.writeObjects([object]) {
                        self.model.count = pb.changeCount
                        self.model.status = "Copied — press Cmd+V in the destination app"
                        guard self.feedbackID == feedback, self.transitionID == presentation, self.open else { return }
                        self.model.copiedID = entry.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                            guard let self, self.feedbackID == feedback, self.transitionID == presentation else { return }
                            self.hide()
                        }
                    } else { self.model.status = "Copy failed" }
                }
            } catch { Task { @MainActor in self.model.copyInFlight = false; self.model.status = "Image file missing: \(error.localizedDescription)" } }
        }
    }
    func menu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: String(model.status.prefix(140)), action: nil, keyEquivalent: ""); status.isEnabled = false; menu.addItem(status); menu.addItem(.separator())
        for (title, selector) in [("Open history  " + model.preferences.shortcutLabel, #selector(openHistory)), (model.paused ? "Resume" : "Pause", #selector(pause)), ("Settings…", #selector(settings)), ("Clear unpinned history", #selector(clear)), ("Delete all…", #selector(clearAll)), ("Quit ClipNest", #selector(quit))] { let row = NSMenuItem(title: title, action: selector, keyEquivalent: ""); row.target = self
            let symbol: String
            switch selector {
            case #selector(settings): symbol = "gearshape"
            case #selector(quit): symbol = "power"
            case #selector(openHistory): symbol = "square.on.square"
            case #selector(pause): symbol = model.paused ? "play" : "pause"
            default: symbol = "trash"
            }
            row.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            if selector == #selector(quit) { row.keyEquivalent = "q" }
            if selector == #selector(settings) { row.keyEquivalent = "," }
            menu.addItem(row) }
        item.menu = menu
    }
    @objc func openHistory() { show(focus: true) }
    @objc func pause() { model.togglePause(); menu() }
    @objc func clear() { model.mutate { $0.clear(all: false) } }
    @objc func clearAll() { let alert = NSAlert(); alert.messageText = "Delete all history and pinned items?"; alert.informativeText = "Locally stored image files will also be deleted."; alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Delete All"); NSApp.activate(ignoringOtherApps: true); if alert.runModal() == .alertSecondButtonReturn { model.mutate { $0.clear(all: true) } } }
    @objc func settings() {
        hide()
        if let window = settingsWindow {
            NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); return
        }
        let view = SettingsView(model: model, retryShortcut: { [weak self] in self?.registerShortcut() })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ClipNest Settings"; window.contentView = NSHostingView(rootView: view)
        window.center(); window.isReleasedWhenClosed = false; settingsWindow = window
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }

    func registerShortcut() {
        if let hotkey { UnregisterEventHotKey(hotkey); self.hotkey = nil }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in delegate.openHistory() }; return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
            if installed != noErr { model.shortcutStatus = "Shortcut handler failed (OSStatus \(installed))"; model.status = model.shortcutStatus; return }
        }
        let result = RegisterEventHotKey(model.preferences.keyCode, model.preferences.modifiers, EventHotKeyID(signature: 0x434C4950, id: 1), GetApplicationEventTarget(), 0, &hotkey)
        model.shortcutStatus = result == noErr ? "Shortcut active" : "Shortcut registration failed / conflict (OSStatus \(result))"
        if result != noErr { model.status = model.shortcutStatus }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { model.save?.cancel(); model.io.sync { try? model.store.flush() } }
}
var validationExitCode: Int32 = 0
MainActor.assumeIsolated {
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
exit(validationExitCode)
}
