import Foundation

struct DatabaseTarget: Codable, Equatable {
    let name: String
    let namespace: String
    let context: String?
    let resource: String?
    let podNamePrefix: String?
    let localPort: Int
    let remotePort: Int

    var endpoint: String { "127.0.0.1:\(localPort)" }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw Configuration.error("Each database needs a name on one line.")
        }
        guard namespace.range(of: #"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\z"#, options: .regularExpression) != nil else {
            throw Configuration.error("\(name): enter a valid Kubernetes namespace.")
        }
        guard (1...65535).contains(localPort), (1...65535).contains(remotePort) else {
            throw Configuration.error("\(name): ports must be between 1 and 65535.")
        }
        if let context, context.isEmpty || context.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
            throw Configuration.error("\(name): context must be a kubeconfig context name, or omit it to use any context.")
        }
        guard (resource == nil) != (podNamePrefix == nil) else {
            throw Configuration.error("\(name): set exactly one of resource or podNamePrefix.")
        }
        if let resource {
            let parts = resource.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, ["service", "pod", "deployment"].contains(String(parts[0])),
                  Self.validResourceName(String(parts[1])) else {
                throw Configuration.error("\(name): resource must be service/name, pod/name, or deployment/name.")
            }
        }
        if let prefix = podNamePrefix {
            guard !prefix.isEmpty, prefix.utf8.count <= 253,
                  prefix.range(of: #"^[a-z0-9][a-z0-9.-]*\z"#, options: .regularExpression) != nil else {
                throw Configuration.error("\(name): podNamePrefix must start with a lowercase letter or digit and contain only lowercase letters, digits, dots, or hyphens.")
            }
        }
    }

    static func validResourceName(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 253 && value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
            $0.range(of: #"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\z"#, options: .regularExpression) != nil
        }
    }
}

struct Configuration: Codable, Equatable {
    var kubeconfig: String? = nil
    var databaseTargets: [DatabaseTarget] = []

    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Docksy/config.json")

    var kubeconfigPath: String? { kubeconfig.map { ($0 as NSString).expandingTildeInPath } }

    func targets(for context: String) -> [DatabaseTarget] {
        databaseTargets.filter { $0.context == nil || $0.context == context }
    }

    func validate() throws {
        if let path = kubeconfigPath {
            guard path.hasPrefix("/"), !path.contains(":"),
                  !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw Self.error("kubeconfig must be one absolute file path (or begin with ~/). Omit it to use kubectl’s default configuration.")
            }
        }
        var names = Set<String>()
        for target in databaseTargets {
            try target.validate()
            guard names.insert(target.name).inserted else { throw Self.error("Duplicate database name: \(target.name).") }
        }
    }

    static func load(from url: URL) throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { return Configuration() }
        let configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
        try configuration.validate()
        return configuration
    }

    static func error(_ message: String) -> NSError {
        NSError(domain: "DocksyConfiguration", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
