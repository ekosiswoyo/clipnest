import Foundation
import CryptoKit
import ImageIO

public struct Representation: Codable, Equatable, Sendable {
    public var type: String
    public var file: String
    public var bytes: Int
    public var digest: String?
}
public struct SourceApp: Codable, Equatable, Sendable {
    public var name: String
    public var bundleID: String?
    public init(name: String, bundleID: String?) { self.name = name; self.bundleID = bundleID }
}
public struct Entry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var sourceApp: SourceApp?
    public var date: Date
    public var pinned: Bool
    public var text: String?
    public var label: String
    public var note: String
    public var digest: String
    public var images: [Representation]
    public var width: Int
    public var height: Int
    public var bytes: Int { text?.utf8.count ?? images.reduce(0) { $0 + $1.bytes } }
}
public enum StoreError: LocalizedError {
    case tooLarge, invalidImage, capacity, metadataCorrupt
    public var errorDescription: String? {
        switch self { case .tooLarge: return "Skipped: exceeds the text limit of 1 MiB or image limits of 20 MiB / 40 MP."
        case .invalidImage: return "Invalid image data or missing file."
        case .metadataCorrupt: return "History metadata is corrupt. Recording stopped; images preserved. Restore a backup or choose Delete All."
        case .capacity: return "Storage is full of pinned items; new items were not saved." }
    }
}
// All mutable access must be serialized by the owner (the app uses its storage queue).
public final class HistoryStore: @unchecked Sendable {
    public private(set) var entries: [Entry] = []
    public let root: URL
    public var maxCount = 100
    public var maxBytes = 200 * 1024 * 1024
    private var retired = Set<String>()
    public private(set) var needsRecovery = false
    private var purgeRecovery = false
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Images"), withIntermediateDirectories: true)
        let metadata = root.appendingPathComponent("history.json")
        needsRecovery = FileManager.default.fileExists(atPath: root.appendingPathComponent("recovery-required").path)
        if FileManager.default.fileExists(atPath: metadata.path) {
            do { entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: metadata)) }
            catch {
                needsRecovery = true
                try Data().write(to: root.appendingPathComponent("recovery-required"), options: .atomic)
                try? FileManager.default.moveItem(at: metadata, to: root.appendingPathComponent("corrupt-\(UUID()).json"))
            }
        }
        entries.removeAll { entry in
            entry.text == nil && (entry.images.isEmpty || entry.images.contains { !Self.safeFile($0.file) || !FileManager.default.fileExists(atPath: imageURL($0.file).path) })
        }
        try flush()
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.appendingPathComponent("Images").path)
    }
    public func imageURL(_ file: String) -> URL { root.appendingPathComponent("Images").appendingPathComponent(file) }
    private static func safeFile(_ name: String) -> Bool { name == URL(fileURLWithPath: name).lastPathComponent && !name.hasPrefix(".") }
    public static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    public static func label(_ text: String) -> String {
        if let d = text.data(using: .utf8), let _ = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]) { return "JSON" }
        if let u = URL(string: text), ["https", "http"].contains(u.scheme?.lowercased() ?? ""), !text.contains(where: { $0.isWhitespace }) { return "URL" }
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["select ", "insert ", "update ", "create table", "with "].contains(where: s.hasPrefix) { return "SQL" }
        if ["$ ", "sudo ", "git ", "npm ", "curl ", "brew "].contains(where: s.hasPrefix) { return "Command" }
        if text.contains("\n") || text.contains("{") || text.contains("\t") { return "Code / Text" }
        return "Text"
    }
    private func insert(_ entry: Entry, payloads: [(String, Data)] = []) throws {
        guard !needsRecovery else { throw StoreError.metadataCorrupt }
        var candidate = entry
        var next = entries
        if let index = entries.firstIndex(where: { old in old.digest == entry.digest || (!entry.images.isEmpty && old.images.contains { rep in entry.images.contains { $0.digest != nil && $0.digest == rep.digest } }) }) {
            var old = entries[index]
            if entry.text != nil || old.digest == entry.digest || Set(entry.images.map(\.type)).isSubset(of: Set(old.images.map(\.type))) {
                entries.remove(at: index); old.date = Date(); old.sourceApp = entry.sourceApp; entries.insert(old, at: 0); return
            }
            // Preserve pin and note while recording the richer original representations.
            candidate.id = old.id; candidate.pinned = old.pinned; candidate.note = old.note
            next.remove(at: index)
        }
        while (!candidate.pinned && next.filter({ !$0.pinned }).count >= maxCount) || next.reduce(0, { $0 + $1.bytes }) + candidate.bytes > maxBytes {
            guard let index = next.indices.reversed().first(where: { !next[$0].pinned }) else { throw StoreError.capacity }
            next.remove(at: index)
        }
        var written: [String] = []
        do {
            for (file, data) in payloads { try data.write(to: imageURL(file), options: .atomic); try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: imageURL(file).path); written.append(file) }
        } catch { for file in written { try? FileManager.default.removeItem(at: imageURL(file)) }; throw error }
        for old in entries where !next.contains(where: { $0.id == old.id }) { retired.formUnion(old.images.map(\.file)) }
        next.insert(candidate, at: 0); entries = next
    }
    public func addText(_ text: String, sourceApp: SourceApp? = nil) throws {
        guard text.utf8.count <= 1024 * 1024 else { throw StoreError.tooLarge }
        guard !text.isEmpty else { return }
        try insert(Entry(id: UUID(), sourceApp: sourceApp, date: Date(), pinned: false, text: text, label: Self.label(text), note: "", digest: "text:" + Self.hash(Data(text.utf8)), images: [], width: 0, height: 0))
    }
    public func addImage(_ representations: [String: Data], sourceApp: SourceApp? = nil) throws {
        guard !representations.isEmpty, representations.values.reduce(0, { $0 + $1.count }) <= 20 * 1024 * 1024 else { throw StoreError.tooLarge }
        var width = 0, height = 0
        for data in representations.values {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let w = properties[kCGImagePropertyPixelWidth] as? Int, let h = properties[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else { throw StoreError.invalidImage }
            guard w <= 40_000_000 / h else { throw StoreError.tooLarge }
            width = w; height = h
        }
        let keys = representations.keys.sorted()
        let digest = "image:" + Self.hash(Data(keys.map { $0 + ":" + Self.hash(representations[$0]!) }.joined(separator: "|").utf8))
        let id = UUID()
        let reps = keys.enumerated().map { index, key in Representation(type: key, file: "\(id)-\(index).image", bytes: representations[key]!.count, digest: Self.hash(representations[key]!)) }
        try insert(Entry(id: id, sourceApp: sourceApp, date: Date(), pinned: false, text: nil, label: "Image", note: "", digest: digest, images: reps, width: width, height: height), payloads: zip(reps, keys).map { ($0.0.file, representations[$0.1]!) })
    }
    public func applyLimits(count: Int, bytes: Int) {
        maxCount = max(1, count); maxBytes = max(1, bytes)
        while entries.filter({ !$0.pinned }).count > maxCount || entries.reduce(0, { $0 + $1.bytes }) > maxBytes {
            guard let oldest = entries.last(where: { !$0.pinned }) else { break }
            delete(oldest.id)
        }
    }
    public func pin(_ id: UUID) {
        if let i = entries.firstIndex(where: { $0.id == id }) { entries[i].pinned.toggle() }
        while entries.filter({ !$0.pinned }).count > maxCount {
            guard let oldest = entries.last(where: { !$0.pinned }) else { break }; delete(oldest.id)
        }
    }
    public func note(_ id: UUID, _ value: String) { if let i = entries.firstIndex(where: { $0.id == id }) { entries[i].note = String(value.prefix(4096)) } }
    public func delete(_ id: UUID) { if let i = entries.firstIndex(where: { $0.id == id }) { retired.formUnion(entries[i].images.map(\.file)); entries.remove(at: i) } }
    public func clear(all: Bool) {
        for e in entries where all || !e.pinned { delete(e.id) }
        if all { needsRecovery = false; purgeRecovery = true }
    }
    public func flush() throws {
        try JSONEncoder().encode(entries).write(to: root.appendingPathComponent("history.json"), options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: root.appendingPathComponent("history.json").path)
        guard !needsRecovery else { return }
        let live = Set(entries.flatMap { $0.images.map(\.file) })
        let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Images"), includingPropertiesForKeys: nil)
        for file in files where !live.contains(file.lastPathComponent) { try? FileManager.default.removeItem(at: file) }
        if purgeRecovery {
            for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where file.lastPathComponent == "recovery-required" || (file.lastPathComponent.hasPrefix("corrupt-") && file.pathExtension == "json") { try FileManager.default.removeItem(at: file) }
            purgeRecovery = false
        }
        retired.removeAll()
    }
}
