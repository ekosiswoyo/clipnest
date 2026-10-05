import Foundation
import AppKit
import ClipNestCore
enum CheckError: Error { case clipboardUnavailable }
final class HistoryTests {
    func store() throws -> HistoryStore { try HistoryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("ClipNestTests-\(UUID())")) }
    func image() -> Data { let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!; return rep.representation(using: .png, properties: [:])! }
    func testExactTextDedupAndPersistence() throws {
        let s = try store(); let text = "\tfunc café() {\r\n  print(\"🪺\")\n}\n  "
        try s.addText(text); try s.addText(text); XCTAssertEqual(s.entries.count, 1); XCTAssertEqual(s.entries[0].text, text); XCTAssertEqual(Data(s.entries[0].text!.utf8), Data(text.utf8))
        try s.addText(text + " "); XCTAssertEqual(s.entries.count, 2)
        try s.flush(); let restored = try HistoryStore(root: s.root); XCTAssertEqual(restored.entries, s.entries)
    }
    func testSourceContextAndLegacyHistory() throws {
        let s = try store()
        let source = SourceApp(name: "Safari", bundleID: "com.apple.Safari")
        try s.addText("context", sourceApp: source)
        let id = s.entries[0].id
        s.pin(id); s.note(id, "Keep this")
        try s.addText("context", sourceApp: SourceApp(name: "Notes", bundleID: "com.apple.Notes"))
        XCTAssertEqual(s.entries[0].id, id); XCTAssertTrue(s.entries[0].pinned)
        XCTAssertEqual(s.entries[0].sourceApp?.name, "Notes"); XCTAssertEqual(s.entries[0].note, "Keep this")
        try s.addImage(["public.png": image()], sourceApp: source)
        try s.flush()
        XCTAssertEqual(try HistoryStore(root: s.root).entries, s.entries)
        // Simulate the metadata written by versions before source context existed.
        var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: s.root.appendingPathComponent("history.json"))) as! [[String: Any]]
        for index in legacy.indices { legacy[index].removeValue(forKey: "sourceApp") }
        try JSONSerialization.data(withJSONObject: legacy).write(to: s.root.appendingPathComponent("history.json"))
        let reopened = try HistoryStore(root: s.root)
        XCTAssertFalse(reopened.needsRecovery); XCTAssertEqual(reopened.entries.count, 2)
        XCTAssertTrue(reopened.entries.allSatisfy { $0.sourceApp == nil })
    }
    func testApplyingPersonalLimits() throws {
        let s = try store()
        try s.addText("pinned"); s.pin(s.entries[0].id)
        try s.addText("old"); try s.addText("middle"); try s.addText("new")
        s.applyLimits(count: 1, bytes: 200 * 1024 * 1024)
        XCTAssertEqual(Set(s.entries.compactMap(\.text)), Set(["pinned", "new"]))
        s.applyLimits(count: 1, bytes: 1)
        XCTAssertEqual(s.entries.count, 1); XCTAssertTrue(s.entries[0].pinned)
        XCTAssertThrowsError(try s.addText("blocked"))
        try s.flush(); XCTAssertEqual(try HistoryStore(root: s.root).entries, s.entries)
    }
    func testEvictionAndPin() throws {
        let s = try store(); s.maxCount = 2
        try s.addText("pin"); s.pin(s.entries[0].id)
        try s.addText("old"); try s.addText("middle"); try s.addText("new")
        XCTAssertEqual(Set(s.entries.compactMap(\.text)), Set(["pin", "middle", "new"]))
        s.maxBytes = s.entries.first(where: \.pinned)!.bytes
        XCTAssertThrowsError(try s.addText("cannot fit"))
        XCTAssertTrue(s.entries.contains(where: \.pinned))
        let unpinStore = try store(); unpinStore.maxCount = 1
        try unpinStore.addText("old pin"); let oldID = unpinStore.entries[0].id; unpinStore.pin(oldID)
        try unpinStore.addText("new"); unpinStore.pin(oldID)
        XCTAssertEqual(unpinStore.entries.count, 1); XCTAssertEqual(unpinStore.entries[0].text, "new"); XCTAssertFalse(unpinStore.entries[0].pinned)
    }
    func testImageLifecycleAndRepresentations() throws {
        let s = try store(); let data = image(); try s.addImage(["public.png": data]); try s.addImage(["public.png": data]); XCTAssertEqual(s.entries.count, 1)
        let entry = s.entries[0]; XCTAssertEqual(entry.width, 64); XCTAssertEqual(entry.height, 32)
        try s.flush(); let restored = try HistoryStore(root: s.root); XCTAssertEqual(try Data(contentsOf: restored.imageURL(entry.images[0].file)), data)
        s.pin(entry.id); s.clear(all: false); try s.flush(); XCTAssertTrue(FileManager.default.fileExists(atPath: s.imageURL(entry.images[0].file).path))
        s.delete(entry.id); try s.flush(); XCTAssertFalse(FileManager.default.fileExists(atPath: s.imageURL(entry.images[0].file).path))
    }
    func testMissingAndCorruptMetadata() throws {
        let s = try store(); try s.addImage(["public.png": image()]); try s.flush(); try FileManager.default.removeItem(at: s.imageURL(s.entries[0].images[0].file)); XCTAssertTrue(try HistoryStore(root: s.root).entries.isEmpty)
        let recovery = try store(); try recovery.addImage(["public.png": image()]); recovery.pin(recovery.entries[0].id); try recovery.flush()
        let preserved = recovery.imageURL(recovery.entries[0].images[0].file)
        try Data("broken".utf8).write(to: recovery.root.appendingPathComponent("history.json"))
        let reopened = try HistoryStore(root: recovery.root); XCTAssertTrue(reopened.needsRecovery); XCTAssertTrue(FileManager.default.fileExists(atPath: preserved.path))
        XCTAssertThrowsError(try reopened.addText("blocked")); XCTAssertTrue(try HistoryStore(root: recovery.root).needsRecovery)
        XCTAssertTrue(FileManager.default.fileExists(atPath: preserved.path))
        reopened.clear(all: true); try reopened.flush(); XCTAssertFalse(FileManager.default.fileExists(atPath: preserved.path))
        let clean = try HistoryStore(root: recovery.root); XCTAssertFalse(clean.needsRecovery); try clean.addText("new")
        try Data("broken".utf8).write(to: s.root.appendingPathComponent("history.json")); XCTAssertTrue(try HistoryStore(root: s.root).entries.isEmpty)
    }
    func testLimitsAndImageEvictionFiles() throws {
        let s = try store(); XCTAssertThrowsError(try s.addText(String(repeating: "x", count: 1024 * 1024 + 1)))
        XCTAssertThrowsError(try s.addImage(["public.png": Data(repeating: 0, count: 20 * 1024 * 1024 + 1)]))
        let oversized = try Data(contentsOf: Bundle.module.url(forResource: "over40mp", withExtension: "png", subdirectory: "Fixtures")!)
        do { try s.addImage(["public.png": oversized]); failures += 1 } catch StoreError.tooLarge {} catch { failures += 1; print("FAIL pixel limit error") }
        s.maxCount = 1; try s.addImage(["public.png": image()]); let file = s.imageURL(s.entries[0].images[0].file); try s.flush(); try s.addText("replacement"); try s.flush(); XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
    func testClipboard() throws {
        let s = try store(); let pb = NSPasteboard(name: NSPasteboard.Name("ClipNestTests-\(UUID())")); defer { pb.releaseGlobally() }
        let text = "\tlet café = \"🪺\"\r\n    // whitespace\n "
        pb.clearContents(); guard pb.setString(text, forType: .string) else { throw CheckError.clipboardUnavailable }
        if case .text(let captured) = try ClipboardCodec.capture(pb) { try s.addText(captured) } else { failures += 1 }
        let object = try ClipboardCodec.item(entry: s.entries[0], store: s); pb.clearContents(); pb.writeObjects([object]); XCTAssertEqual(pb.string(forType: .string), text)
        if case .ignored = try ClipboardCodec.capture(pb) {} else { failures += 1 }
        let png = image(); try s.addImage(["public.png": png]); s.pin(s.entries[0].id); let imageID = s.entries[0].id; let bitmap = NSBitmapImageRep(data: png)!; let tiff = bitmap.tiffRepresentation!
        let source = NSPasteboardItem(); source.setData(png, forType: .png); source.setData(tiff, forType: .tiff); source.setString("caption", forType: .string); pb.clearContents(); pb.writeObjects([source])
        if case .image(let reps) = try ClipboardCodec.capture(pb) { try s.addImage(reps) } else { failures += 1 }
        XCTAssertEqual(s.entries.count, 2); XCTAssertEqual(s.entries[0].images.count, 2); XCTAssertEqual(s.entries[0].id, imageID); XCTAssertTrue(s.entries[0].pinned)
        try s.addImage(["public.png": png]); XCTAssertEqual(s.entries.count, 2)
        try s.flush(); let restored = try HistoryStore(root: s.root)
        let copied = try ClipboardCodec.item(entry: restored.entries[0], store: restored); pb.clearContents(); pb.writeObjects([copied])
        XCTAssertEqual(pb.data(forType: .png), png); XCTAssertEqual(pb.data(forType: .tiff), tiff); XCTAssertEqual(pb.string(forType: .string), nil)
        let decoded = NSBitmapImageRep(data: pb.data(forType: .png)!)!; XCTAssertEqual(decoded.pixelsWide, 64); XCTAssertEqual(decoded.pixelsHigh, 32); XCTAssertTrue(decoded.hasAlpha)
        let privateItem = NSPasteboardItem(); privateItem.setString("secret", forType: .string); privateItem.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")); pb.clearContents(); pb.writeObjects([privateItem]); if case .ignored = try ClipboardCodec.capture(pb) {} else { failures += 1 }
    }

}

var failures = 0
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { if a != b { failures += 1; print("FAIL equality") } }
func XCTAssertTrue(_ value: Bool) { if !value { failures += 1; print("FAIL true") } }
func XCTAssertFalse(_ value: Bool) { XCTAssertTrue(!value) }
func XCTAssertThrowsError(_ value: @autoclosure () throws -> Void) { do { try value(); failures += 1; print("FAIL expected error") } catch {} }
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--seed" {
    let s = try HistoryStore(root: URL(fileURLWithPath: CommandLine.arguments[2]))
    s.clear(all: true)
    for index in 0..<50 {
        try s.addText("// fixture \(index)\n" + String(repeating: "\tlet emoji = \"🪺\"\n", count: 1000))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 768, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let bytes = rep.bitmapData!; var random = UInt32(index + 1)
        for pixel in 0..<(1024 * 768) { random = random &* 1664525 &+ 1013904223; bytes[pixel * 4] = UInt8(truncatingIfNeeded: random); bytes[pixel * 4 + 1] = UInt8(truncatingIfNeeded: random >> 8); bytes[pixel * 4 + 2] = UInt8(truncatingIfNeeded: random >> 16); bytes[pixel * 4 + 3] = 128 }
        try s.addImage(["public.png": rep.representation(using: .png, properties: [:])!])
    }
    try s.flush(); print("Seed: \(s.entries.count) items, \(s.entries.reduce(0) { $0 + $1.bytes }) bytes"); exit(0)
}
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--seed-large" {
    let s = try HistoryStore(root: URL(fileURLWithPath: CommandLine.arguments[2])); s.clear(all: true)
    try s.addText("SELECT id, name\nFROM developers\nWHERE active = true;")
    try s.addText("{\n  \"app\": \"ClipNest\",\n  \"local\": true\n}")
    try s.addText("func greet(_ name: String) {\n\tprint(\"Hello, \\(name) 🪺\")\n}\n")
    try s.addImage(["public.png": Data(contentsOf: Bundle.module.url(forResource: "large24mp", withExtension: "png", subdirectory: "Fixtures")!)])
    s.note(s.entries[0].id, "Fixture transparan 24 MP"); try s.flush(); print("Large image fixture seeded"); exit(0)
}
let tests = HistoryTests()
for (name, test) in [("source context / legacy metadata", tests.testSourceContextAndLegacyHistory), ("personal history limits", tests.testApplyingPersonalLimits), ("exact text / dedup / restart", tests.testExactTextDedupAndPersistence), ("eviction / pins / capacity", tests.testEvictionAndPin), ("image payload / lifecycle", tests.testImageLifecycleAndRepresentations), ("missing / corrupt metadata", tests.testMissingAndCorruptMetadata), ("size limits / image eviction", tests.testLimitsAndImageEvictionFiles), ("clipboard round trip / privacy", tests.testClipboard)] {
    do { try test(); print("CHECK \(name)") } catch { failures += 1; print("FAIL \(name): \(error)") }
}
print("Failures: \(failures)")
exit(failures == 0 ? 0 : 1)
