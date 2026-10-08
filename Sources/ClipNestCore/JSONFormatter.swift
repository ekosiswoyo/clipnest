import Foundation

public enum JSONFormatter {
    /// Returns readable JSON, or nil when the text is not valid JSON.
    public static func format(_ text: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
              let formatted = String(data: data, encoding: .utf8) else { return nil }
        return formatted
    }
}
