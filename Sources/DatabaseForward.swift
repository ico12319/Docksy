import Foundation
import Darwin

struct KubernetesContextSnapshot {
    // Project only names, never credentials, from the merged kubeconfig.
    static let arguments = ["config", "view", #"--output=jsonpath={.current-context}{"\n"}{range .contexts[*]}{.name}{"\n"}{end}"#]
    let current: String?
    let contexts: [String]

    init(output: String) {
        let lines = output.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        current = lines[0].isEmpty ? nil : String(lines[0])
        contexts = lines.count > 1 ? DatabaseKubectl.contexts(from: String(lines[1])) : []
    }

    static func useArguments(context: String) -> [String] {
        ["config", "use-context", "--", context]
    }
}

enum DatabaseKubectl {
    static func contexts(from output: String) -> [String] {
        Array(Set(output.split(whereSeparator: \.isNewline).map(String.init))).sorted()
    }

    static func podArguments(context: String, target: DatabaseTarget) -> [String] {
        ["--context=\(context)", "--namespace=\(target.namespace)", "get", "pods", "--output=json", "--request-timeout=20s"]
    }

    static func forwardArguments(context: String, target: DatabaseTarget, resource: String) -> [String] {
        ["--context=\(context)", "--namespace=\(target.namespace)", "port-forward", resource,
         "\(target.localPort):\(target.remotePort)", "--address=127.0.0.1", "--pod-running-timeout=20s"]
    }

    static func matchingPod(from data: Data, prefix: String) throws -> String {
        struct PodList: Decodable {
            struct Pod: Decodable {
                struct Metadata: Decodable { let name: String; let deletionTimestamp: String? }
                struct Status: Decodable {
                    struct Condition: Decodable { let type: String; let status: String }
                    let phase: String?
                    let conditions: [Condition]?
                }
                let metadata: Metadata
                let status: Status?
                var ready: Bool { status?.conditions?.contains { $0.type == "Ready" && $0.status == "True" } == true }
            }
            let items: [Pod]
        }
        let pods = try JSONDecoder().decode(PodList.self, from: data).items.filter {
            let name = $0.metadata.name
            return name.hasPrefix(prefix) && DatabaseTarget.validResourceName(name)
                && $0.metadata.deletionTimestamp == nil && $0.status?.phase == "Running"
        }.sorted {
            $0.ready != $1.ready ? $0.ready : $0.metadata.name < $1.metadata.name
        }
        guard let pod = pods.first else {
            throw NSError(domain: "DocksyDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "No running pod matching \(prefix)* was found in the configured namespace."])
        }
        return pod.metadata.name
    }
}

struct DatabaseForwardState {
    enum Phase { case idle, findingPod, starting, forwarding, stopping, failed }
    private(set) var phase: Phase = .idle
    private(set) var context: String?
    private(set) var error: String?
    private(set) var request = UUID()
    private var output = ""
    private var localPort = 0
    var isBusy: Bool { [.findingPod, .starting, .forwarding, .stopping].contains(phase) }

    mutating func begin(context: String, localPort: Int) -> UUID? {
        guard !isBusy, !context.isEmpty, (1...65535).contains(localPort) else { return nil }
        self.context = context
        self.localPort = localPort
        phase = .findingPod
        error = nil
        output = ""
        request = UUID()
        return request
    }

    mutating func foundPod(for request: UUID) -> Bool {
        guard self.request == request, phase == .findingPod else { return false }
        phase = .starting
        return true
    }

    mutating func received(_ text: String, for request: UUID) -> Bool {
        guard self.request == request, phase == .starting else { return false }
        let combined = output + text
        output = String(combined.suffix(1024))
        // Services can resolve to a different pod port; readiness is for the local listener.
        guard combined.contains("Forwarding from 127.0.0.1:\(localPort) -> ") else { return false }
        phase = .forwarding
        output = ""
        return true
    }

    mutating func stop() {
        if isBusy { phase = .stopping }
    }

    mutating func finished(_ request: UUID, error: String) {
        guard self.request == request, isBusy else { return }
        if phase == .stopping {
            phase = .idle
            context = nil
            self.error = nil
        } else {
            phase = .failed
            self.error = error
        }
    }
}

func readKubectlPipe(_ handle: FileHandle, isRunning: () -> Bool, onData: (Data) -> Void) throws {
    defer { try? handle.close() }
    let fd = handle.fileDescriptor
    var buffer = [UInt8](repeating: 0, count: 8192)
    while true {
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
        let ready = poll(&descriptor, 1, 200)
        if ready == 0 {
            // Auth helpers may retain the pipe; once kubectl exits, do not wait for their EOF.
            if !isRunning() { return }
            continue
        }
        if ready < 0 {
            if errno == EINTR { continue }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        // One POSIX read delivers the readiness line immediately, without filling an 8 KB buffer.
        let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
        if count == 0 { return }
        if count < 0 {
            if errno == EINTR { continue }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        onData(Data(buffer.prefix(count)))
    }
}

// All callbacks and mutable job state belong to the main thread; pipe reads run in the background.
private final class KubectlJob {
    struct Result {
        let output: Data
        let error: String?
    }
    private let process = Process()
    private var output = Data()
    private var errors = Data()
    private var timeout: DispatchWorkItem?
    private var failure: String?
    private var completed = false

    func start(arguments: [String], kubeconfig: String?, captureOutput: Bool = true,
               onOutput: @escaping (String) -> Void = { _ in }, completion: @escaping (Result) -> Void) {
        var environment = ProcessInfo.processInfo.environment
        if let kubeconfig { environment["KUBECONFIG"] = kubeconfig }
        let paths = [NSHomeDirectory() + "/.krew/bin", NSHomeDirectory() + "/.local/bin", NSHomeDirectory() + "/go/bin",
                     "/usr/local/bin", "/opt/homebrew/bin", "/opt/homebrew/share/google-cloud-sdk/bin",
                     environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]
        environment["PATH"] = paths.joined(separator: ":")
        let candidates = ["/usr/local/bin/kubectl", "/opt/homebrew/bin/kubectl"] +
            paths.joined(separator: ":").split(separator: ":").map { String($0) + "/kubectl" }
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            completion(Result(output: Data(), error: "kubectl was not found. Install it or add it to the app’s PATH."))
            return
        }
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        do { try process.run() }
        catch { completion(Result(output: Data(), error: error.localizedDescription)); return }

        let readers = DispatchGroup()
        for (pipe, isError) in [(stdout, false), (stderr, true)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                do {
                    try readKubectlPipe(pipe.fileHandleForReading, isRunning: { self.process.isRunning }) { chunk in
                        DispatchQueue.main.async {
                            guard !self.completed else { return }
                            if isError { self.errors = Data((self.errors + chunk).suffix(8192)) }
                            else {
                                if captureOutput {
                                    if self.output.count + chunk.count <= 8 * 1024 * 1024 { self.output.append(chunk) }
                                    else if self.failure == nil {
                                        self.failure = "kubectl returned more output than the app can safely display."
                                        self.stop()
                                    }
                                }
                                onOutput(String(decoding: chunk, as: UTF8.self))
                            }
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.failure = self.failure ?? "Could not read kubectl output: \(error.localizedDescription)"
                        self.stop()
                    }
                }
                readers.leave()
            }
        }
        DispatchQueue.global(qos: .utility).async {
            self.process.waitUntilExit()
            readers.wait()
            DispatchQueue.main.async {
                self.completed = true
                self.cancelTimeout()
                let detail = String(decoding: self.errors, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                let error = self.failure ?? (self.process.terminationStatus == 0 ? nil :
                    (detail.isEmpty ? "kubectl exited with status \(self.process.terminationStatus)." : detail))
                completion(Result(output: self.output, error: error))
            }
        }
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.process.isRunning else { return }
            self.failure = "kubectl did not finish within 60 seconds. Check your configuration and, for cluster connections, your VPN and Kubernetes login."
            self.stop()
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timeout)
    }

    func cancelTimeout() { timeout?.cancel(); timeout = nil }

    func stop() {
        cancelTimeout()
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}

final class DatabaseForwarder {
    private(set) var configuration = Configuration()
    private(set) var target: DatabaseTarget?
    private(set) var contexts: [String] = []
    private(set) var currentContext: String?
    private(set) var switchingContext: String?
    private(set) var contextsError: String?
    private(set) var loadingContexts = false
    private(set) var state = DatabaseForwardState()
    var onChange: (() -> Void)?
    private var contextJob: KubectlJob?
    private var activeJob: KubectlJob?
    private var shuttingDown = false
    var isBusy: Bool { state.isBusy || switchingContext != nil }
    var canConfigure: Bool { !isBusy && contextJob == nil && !shuttingDown }

    func configure(_ configuration: Configuration) throws {
        guard canConfigure else { throw Configuration.error("Stop the port-forward and wait for context operations before reloading settings.") }
        try configuration.validate()
        self.configuration = configuration
        contexts = []
        currentContext = nil
        target = nil
        state = DatabaseForwardState()
        refreshContexts()
        onChange?()
    }

    func refreshContexts() {
        guard contextJob == nil, !shuttingDown else { return }
        loadingContexts = true
        contextsError = nil
        let job = KubectlJob()
        contextJob = job
        job.start(arguments: KubernetesContextSnapshot.arguments, kubeconfig: configuration.kubeconfigPath) { [weak self] result in
            guard let self else { return }
            self.contextJob = nil
            self.loadingContexts = false
            self.contextsError = result.error
            let snapshot = KubernetesContextSnapshot(output: String(decoding: result.output, as: UTF8.self))
            self.contexts = result.error == nil ? snapshot.contexts : []
            self.currentContext = result.error == nil ? snapshot.current : nil
            self.onChange?()
        }
    }

    func useContext(_ context: String, completion: @escaping (String?) -> Void) {
        guard !shuttingDown, contextJob == nil, contexts.contains(context), context != currentContext else { return }
        let job = KubectlJob()
        contextJob = job
        switchingContext = context
        onChange?()
        job.start(arguments: KubernetesContextSnapshot.useArguments(context: context), kubeconfig: configuration.kubeconfigPath) { [weak self] result in
            guard let self else { return }
            self.contextJob = nil
            self.switchingContext = nil
            // Re-read after both success and failure; the file is the source of truth.
            self.refreshContexts()
            self.onChange?()
            if !self.shuttingDown { completion(result.error) }
        }
    }

    func start(context: String, target: DatabaseTarget) {
        guard !shuttingDown, switchingContext == nil, contexts.contains(context),
              configuration.targets(for: context).contains(target),
              let request = state.begin(context: context, localPort: target.localPort) else { return }
        self.target = target
        onChange?()
        if let resource = target.resource {
            guard state.foundPod(for: request) else { return }
            forward(context: context, target: target, resource: resource, request: request)
            return
        }
        let job = KubectlJob()
        activeJob = job
        job.start(arguments: DatabaseKubectl.podArguments(context: context, target: target), kubeconfig: configuration.kubeconfigPath) { [weak self] result in
            guard let self else { return }
            if let error = result.error { self.finish(request, error: error); return }
            guard self.state.foundPod(for: request) else {
                self.finish(request, error: "Port-forward cancelled.")
                return
            }
            do {
                let pod = try DatabaseKubectl.matchingPod(from: result.output, prefix: target.podNamePrefix!)
                self.forward(context: context, target: target, resource: "pod/\(pod)", request: request)
            } catch { self.finish(request, error: error.localizedDescription) }
        }
    }

    private func forward(context: String, target: DatabaseTarget, resource: String, request: UUID) {
        let job = KubectlJob()
        activeJob = job
        onChange?()
        job.start(arguments: DatabaseKubectl.forwardArguments(context: context, target: target, resource: resource),
                  kubeconfig: configuration.kubeconfigPath, captureOutput: false,
                  onOutput: { [weak self, weak job] text in
            guard let self else { return }
            if self.state.received(text, for: request) {
                job?.cancelTimeout()
                self.onChange?()
            }
        }, completion: { [weak self] result in
            self?.finish(request, error: result.error ?? "The database port-forward ended. Select the cluster again to reconnect.")
        })
    }

    private func finish(_ request: UUID, error: String) {
        guard state.request == request else { return }
        activeJob = nil
        state.finished(request, error: error)
        onChange?()
    }

    func stop() {
        guard state.isBusy else { return }
        state.stop()
        activeJob?.stop()
        onChange?()
    }

    func shutdown() {
        shuttingDown = true
        // Let an in-flight kubeconfig write finish before the app exits.
        if switchingContext == nil { contextJob?.stop() }
        stop()
    }
}
