import Foundation

enum TerminalApp: String, CaseIterable {
    case terminal = "com.apple.Terminal"
    case iterm = "com.googlecode.iterm2"

    var name: String { self == .terminal ? "Terminal" : "iTerm2" }
}

struct CodexSession: Equatable {
    let tty: String
    let app: TerminalApp?

    var title: String { "\(app?.name ?? "Codex") · \(tty)" }
}

func normalizedTTY(_ value: String) -> String? {
    let name = value.hasPrefix("/dev/") ? String(value.dropFirst(5)) : value
    let suffix: Substring
    if name.hasPrefix("ttys") { suffix = name.dropFirst(4) }
    else if name.hasPrefix("s") { suffix = name.dropFirst() }
    else { return nil }
    guard !suffix.isEmpty, suffix.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
    return "ttys" + suffix
}

func codexSessions(from output: String) -> [CodexSession] {
    struct ProcessInfo {
        let parent: Int
        let tty: String
        let executable: String
    }
    var processes: [Int: ProcessInfo] = [:]
    for line in output.split(separator: "\n") {
        let fields = line.split(maxSplits: 3, whereSeparator: { $0.isWhitespace })
        guard fields.count == 4, let pid = Int(fields[0]), let parent = Int(fields[1]) else { continue }
        processes[pid] = ProcessInfo(parent: parent, tty: String(fields[2]), executable: String(fields[3]))
    }

    var sessions: [String: CodexSession] = [:]
    for (pid, process) in processes {
        let name = (process.executable as NSString).lastPathComponent
        guard ["codex", "codex-aarch64-apple-darwin", "codex-x86_64-apple-darwin"].contains(name),
              let tty = normalizedTTY(process.tty) else { continue }
        var app: TerminalApp?
        var ancestor = pid
        var seen = Set<Int>()
        while let parent = processes[ancestor], seen.insert(ancestor).inserted {
            let executable = (parent.executable as NSString).lastPathComponent
            if executable == "Terminal" { app = .terminal; break }
            if executable == "iTerm2" { app = .iterm; break }
            ancestor = parent.parent
        }
        if sessions[tty] == nil || app != nil {
            sessions[tty] = CodexSession(tty: tty, app: app)
        }
    }
    return sessions.values.sorted { $0.tty < $1.tty }
}

func discoverSessions() throws -> [CodexSession] {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-x", "-ww", "-o", "pid=,ppid=,tty=,comm="]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "DocksyMascot", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "macOS could not list your running Codex sessions."])
    }
    return codexSessions(from: String(decoding: data, as: UTF8.self))
}
