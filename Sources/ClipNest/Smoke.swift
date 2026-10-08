import AppKit
import ClipNestCore

extension AppDelegate {
    @MainActor func smoke() async {
        guard ProcessInfo.processInfo.environment["CLIPNEST_DATA_DIR"] != nil else { print("Smoke test requires isolated CLIPNEST_DATA_DIR"); NSApp.terminate(nil); return }
        let pb = NSPasteboard.general
        let original = (pb.pasteboardItems ?? []).map { old -> NSPasteboardItem in
            let item = NSPasteboardItem(); for type in old.types { if let data = old.data(forType: type) { item.setData(data, forType: type) } }; return item
        }
        var failures = 0
        func check(_ condition: Bool, _ name: String) { print("\(condition ? "PASS" : "FAIL") \(name)"); if !condition { failures += 1 } }
        func settle() async { try? await Task.sleep(nanoseconds: 250_000_000) }
        model.mutate { $0.clear(all: true) }; await settle()
        let text = "\tfunc café() {\r\n    print(\"🪺\")\n}\n "
        pb.clearContents(); pb.setString(text, forType: .string); model.poll(); await settle()
        check(model.entries.count == 1 && model.entries[0].text == text, "app captures exact multiline Unicode")
        if let entry = model.entries.first { copy(entry, nil) }; await settle()
        check(pb.string(forType: .string) == text, "app copies exact original text")
        model.poll(); await settle(); check(model.entries.count == 1, "self-copy does not loop")
        model.togglePause(); pb.clearContents(); pb.setString("paused fixture", forType: .string); model.poll(); model.togglePause(); model.poll(); await settle()
        check(model.entries.count == 1, "pause / resume skips paused clipboard")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        memset(bitmap.bitmapData!, 0, bitmap.bytesPerRow * bitmap.pixelsHigh)
        bitmap.setColor(NSColor(calibratedRed: 1, green: 0.5, blue: 0.2, alpha: 0.25), atX: 10, y: 10)
        let png = bitmap.representation(using: .png, properties: [:])!, tiff = bitmap.tiffRepresentation!
        let item = NSPasteboardItem(); item.setData(png, forType: .png); item.setData(tiff, forType: .tiff); item.setString("caption fixture", forType: .string)
        pb.clearContents(); pb.writeObjects([item]); model.poll(); await settle()
        check(model.entries.count == 2 && model.entries.first?.images.count == 2, "image wins over caption / one item")
        model.io.sync { try? model.store.flush() }
        if let restored = try? HistoryStore(root: model.store.root), let entry = restored.entries.first {
            copy(entry, nil); await settle()
            check(pb.data(forType: .png) == png && pb.data(forType: .tiff) == tiff && pb.string(forType: .string) == nil, "restart reload / original full image representations")
            if let decoded = NSBitmapImageRep(data: pb.data(forType: .png) ?? Data()) { check(decoded.pixelsWide == 128 && decoded.pixelsHigh == 64 && decoded.hasAlpha && (decoded.colorAt(x: 10, y: 10)?.alphaComponent ?? 1) < 0.3, "original dimensions and transparency") } else { check(false, "PNG decode") }
            model.mutate { $0.pin(entry.id); $0.clear(all: false) }; await settle()
            check(model.entries.count == 1 && model.entries.first?.pinned == true, "pin survives ordinary cleanup")
        } else { check(false, "restart reload") }
        hide()
        await settle()
        let start = Date(), screenFrame = NSScreen.screens.first!.frame
        let away = NSPoint(x: screenFrame.minX + 4, y: screenFrame.minY + 4)
        let hoverPoint = NSPoint(x: trigger.midX, y: trigger.minY + 4)
        hover(point: away, now: start)
        check(!open && !panel.isVisible && trigger.width > 0, "idle stays invisible with an active hover trigger")
        hover(point: hoverPoint, now: start.addingTimeInterval(1))
        check(open && !panel.isKeyWindow, "first hover detection opens immediately without click or keyboard focus")
        hover(point: NSPoint(x: panel.frame.midX, y: panel.frame.midY), now: start.addingTimeInterval(2))
        check(open, "pointer inside history keeps panel open")
        hover(point: away, now: start.addingTimeInterval(3))
        hover(point: away, now: start.addingTimeInterval(3.49))
        check(open, "exit delay prevents flicker")
        hover(point: away, now: start.addingTimeInterval(3.51))
        await settle()
        check(!open && !panel.isVisible, "panel closes invisibly after hover exit delay")
        show(focus: false); check(!panel.isKeyWindow, "hover open does not take keyboard focus")
        check(panel.contentView?.acceptsFirstMouse(for: nil) == true, "history buttons accept first click in inactive hover panel")
        if let entry = model.entries.first {
            let wasPinned = entry.pinned
            model.mutate { $0.pin(entry.id) }
            await settle()
            check(model.entries.first(where: { $0.id == entry.id })?.pinned == !wasPinned, "pin action updates visible history")
            model.mutate { $0.pin(entry.id) }
            await settle()
            check(model.entries.first(where: { $0.id == entry.id })?.pinned == wasPinned, "unpin action updates visible history")
        }
        model.dragging = true
        hover(point: away, now: start.addingTimeInterval(10))
        hover(point: away, now: start.addingTimeInterval(12))
        check(open, "dragging keeps panel open outside its bounds")
        model.dragging = false
        await settle()
        func searchField(in view: NSView) -> SearchTextField? {
            if let field = view as? SearchTextField { return field }
            return view.subviews.lazy.compactMap { searchField(in: $0) }.first
        }
        if let content = panel.contentView, let field = searchField(in: content) {
            check(field.acceptsFirstMouse(for: nil), "search accepts first click in hover panel")
            field.focusPanel?()
            panel.makeFirstResponder(field)
            if let editor = panel.firstResponder as? NSTextView {
                editor.selectAll(nil)
                editor.insertText("no-match-typed-fixture", replacementRange: editor.selectedRange())
                await settle()
                check(panel.isKeyWindow && model.query == "no-match-typed-fixture" && model.filtered.isEmpty, "search typing activates hover panel and filters history")
                model.query = ""
                await settle()
                check(field.stringValue.isEmpty && !model.filtered.isEmpty, "clearing search restores field and history")
            } else { check(false, "search receives text editor focus") }
        } else { check(false, "search field exists in hover panel") }
        model.query = "no-match-footer-fixture"
        check(model.activeEntry == nil, "footer has no action for an empty search")
        model.query = ""
        check(model.activeEntry?.id == model.entries.first?.id, "footer resolves selected visible item")
        let frame = panel.frame; geometry(); check(frame == panel.frame, "stable panel geometry")
        hide(); show(focus: true); await settle(); check(panel.isKeyWindow, "shortcut open takes focus")
        if let entry = model.entries.first {
            copy(entry, nil); await settle()
            check(model.copiedID == entry.id && open, "copy feedback remains visible before closing")
            try? await Task.sleep(nanoseconds: 550_000_000)
            check(!open && !panel.isVisible && model.copiedID == nil, "copy feedback closes and resets")
        }
        let originalEntries = model.entries
        if var image = originalEntries.first {
            image.pinned = true
            var textEntry = image
            textEntry.id = UUID(); textEntry.text = "Filter fixture"; textEntry.label = "Text"; textEntry.pinned = false
            model.entries = [textEntry, image]
            check(model.filtered.map(\.id) == [image.id, textEntry.id], "pinned entries appear first without changing history order")
            model.filter = .text
            check(model.filtered.map(\.id) == [textEntry.id], "text filter excludes images")
            model.filter = .images
            check(model.filtered.map(\.id) == [image.id], "image filter excludes text")
            model.filter = .pinned
            check(model.filtered.map(\.id) == [image.id], "pinned filter excludes unpinned entries")
            model.query = "absent-filter-query"
            check(model.filtered.isEmpty && model.activeEntry == nil, "search combines with filters and clears hidden selection")
            model.query = ""; model.filter = .all
            model.entries = originalEntries
        }
        model.pasteStatus = "Paste failed — fixture"
        model.status = "Saved locally"
        check(model.displayStatus == "Paste failed — fixture", "paste feedback survives clipboard updates")
        model.pasteStatus = nil
        let originalPreferences = model.preferences
        if let data = try? JSONEncoder().encode(originalPreferences),
           var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            object.removeValue(forKey: "savedCompactCards")
            object.removeValue(forKey: "savedTextSize")
            object.removeValue(forKey: "savedOpacity")
            let legacy = try? JSONSerialization.data(withJSONObject: object)
            let decoded = legacy.flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }
            check(decoded?.theme == originalPreferences.theme && decoded?.compactCards == true && decoded?.textSize == 13, "older settings retain theme and receive display defaults")
        }
        model.preferences.compactCards = false
        model.preferences.textSize = 16
        model.preferences.panelOpacity = 0.8
        model.preferences.hoverEnabled = false
        hover(point: away); hover(point: hoverPoint)
        check(!open, "disabled hover keeps panel closed")
        model.preferences.theme = "Light"
        model.preferences.hoverDelay = 0.25
        let reloaded = Model()
        check(reloaded.preferences == model.preferences, "personal settings persist across model reload")
        model.preferences = originalPreferences
        hide()
        pb.clearContents(); if !original.isEmpty { pb.writeObjects(original) }; model.count = pb.changeCount
        validationExitCode = failures == 0 ? 0 : 1
        print("SMOKE failures: \(failures)"); fflush(stdout)
        NSApp.terminate(nil)
    }
}

extension AppDelegate {
    @MainActor private func capture(_ view: NSView, name: String) {
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: model.store.root.appendingPathComponent(name), options: .atomic) }
        }
    }
    @MainActor private func capturePanel(_ name: String) { if let view = panel.contentView { capture(view, name: name) } }
    @MainActor func panelCheck() async {
        guard ProcessInfo.processInfo.environment["CLIPNEST_DATA_DIR"] != nil else { NSApp.terminate(nil); return }
        var last = ProcessInfo.processInfo.systemUptime, maximumGap = 0.0
        let heartbeat = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            let now = ProcessInfo.processInfo.systemUptime; maximumGap = max(maximumGap, now - last); last = now
        }
        show(focus: true)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        heartbeat.invalidate()
        if let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: model.store.root.appendingPathComponent("panel.png"), options: .atomic) }
        }
        model.query = "no-matching-item-87234"
        try? await Task.sleep(nanoseconds: 300_000_000)
        capturePanel("empty-search.png")
        model.query = ""
        model.preferences.theme = "Light"
        try? await Task.sleep(nanoseconds: 300_000_000)
        capturePanel("panel-light.png")
        model.preferences.theme = "Black"
        try? await Task.sleep(nanoseconds: 300_000_000)
        capturePanel("panel-black.png")
        model.preferences.theme = "Light"
        let snapshot = model.entries
        model.entries = []
        try? await Task.sleep(nanoseconds: 300_000_000)
        capturePanel("empty-history.png")
        model.entries = snapshot
        if var fixture = snapshot.first {
            fixture.text = "{\"message\":\"Footer layout fixture\",\"items\":[1,2,3]}"
            fixture.label = "JSON"
            fixture.images = []
            model.entries = (0..<12).map { index in var entry = fixture; entry.id = UUID(); entry.pinned = index == 2; return entry }
            model.selected = model.entries.first?.id
            model.pasteDestination = "An application with a very long destination name"
            try? await Task.sleep(nanoseconds: 300_000_000)
            capturePanel("footer-populated.png")
            model.preferences.theme = "Black"
            try? await Task.sleep(nanoseconds: 300_000_000)
            capturePanel("black-populated.png")
            model.preferences.compactCards = false
            model.preferences.textSize = 16
            model.pasteStatus = "Paste failed — focus a text field in another app, then reopen history"
            try? await Task.sleep(nanoseconds: 300_000_000)
            capturePanel("large-text-status.png")
            model.preferences.theme = "Light"
            model.preferences.compactCards = true
            model.preferences.textSize = 13
            model.pasteStatus = nil
            model.entries = snapshot
            model.selected = snapshot.first?.id
        }
        model.copiedID = snapshot.first?.id
        try? await Task.sleep(nanoseconds: 300_000_000)
        capturePanel("copy-feedback.png")
        model.copiedID = nil
        settings()
        try? await Task.sleep(nanoseconds: 500_000_000)
        if let view = settingsWindow?.contentView { capture(view, name: "settings.png") }
        print("PANEL CHECK: items=\(model.entries.count), maxMainTimerGapMs=\(Int(maximumGap * 1000)), visible=\(panel.isVisible)"); fflush(stdout)
        hide(); NSApp.terminate(nil)
    }
}
