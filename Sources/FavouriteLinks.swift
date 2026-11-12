import Foundation

enum FavouriteLinks {
    static let defaults: [String: String] = [:]

    static func webURL(_ value: String) -> URL? {
        guard !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty else { return nil }
        return URL(string: value)
    }

    static func adding(name: String, address: String, to links: [String: String]) throws -> [String: String] {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw NSError(domain: "DocksyLinks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter a link name on one line."])
        }
        guard webURL(address) != nil else {
            throw NSError(domain: "DocksyLinks", code: 2, userInfo: [NSLocalizedDescriptionKey: "Enter a complete http:// or https:// URL without spaces."])
        }
        guard links[name] == nil else {
            throw NSError(domain: "DocksyLinks", code: 3, userInfo: [NSLocalizedDescriptionKey: "A favourite named ‘\(name)’ already exists. Choose a different name."])
        }
        var updated = links
        updated[name] = address
        return updated
    }
}
