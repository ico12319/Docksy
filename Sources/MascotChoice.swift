import Foundation

enum MascotChoice: String, CaseIterable {
    case gopher, cat, dog

    init(savedValue: String?) {
        self = savedValue.flatMap(Self.init(rawValue:)) ?? .gopher
    }

    var title: String { rawValue.capitalized }

    func artworkURL(resources: URL, personalDirectory: URL) -> URL {
        let personal = personalDirectory.appendingPathComponent("gopher.png")
        if self == .gopher, FileManager.default.fileExists(atPath: personal.path) { return personal }
        return resources.appendingPathComponent("\(rawValue).png")
    }
}
