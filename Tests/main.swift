import Foundation
import CoreGraphics
import AppKit

assert(MascotChoice(savedValue: nil) == .gopher, "Existing installations keep their gopher")
assert(MascotChoice(savedValue: "unknown") == .gopher, "An unknown saved choice falls back to the gopher")
let preferenceDomain = "local.usrv.gopher.unit-tests.\(UUID().uuidString)"
let preferences = UserDefaults(suiteName: preferenceDomain)!
for choice in MascotChoice.allCases {
    preferences.set(choice.rawValue, forKey: "SelectedMascot")
    assert(MascotChoice(savedValue: preferences.string(forKey: "SelectedMascot")) == choice)
    let url = URL(fileURLWithPath: "assets/\(choice.rawValue).png")
    let bitmap = NSBitmapImageRep(data: try Data(contentsOf: url))!
    assert(bitmap.hasAlpha, "Every mascot must have a transparent background")
    assert(bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0, "The background must be transparent pixels")
    let image = NSImage(contentsOf: url)!
    assert(image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil)
    let before = CGRect(x: -100, y: 300, width: 105, height: 114)
    let after = resizedMascotFrame(before, height: before.height, aspectRatio: image.size.width / image.size.height)
    assert(after.height == before.height && abs(after.midX - before.midX) < 0.000001 && abs(after.midY - before.midY) < 0.000001,
           "Changing mascot proportions preserves the saved height and center")
}
preferences.removePersistentDomain(forName: preferenceDomain)
print("Mascot preference, fallback, transparent artwork, and switch geometry unit checks passed.")

let artworkResources = URL(fileURLWithPath: "assets", isDirectory: true)
let personalArtwork = FileManager.default.temporaryDirectory.appendingPathComponent("docksy-artwork-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: personalArtwork, withIntermediateDirectories: true)
for choice in MascotChoice.allCases {
    assert(choice.artworkURL(resources: artworkResources, personalDirectory: personalArtwork) == artworkResources.appendingPathComponent("\(choice.rawValue).png"))
    try FileManager.default.copyItem(at: artworkResources.appendingPathComponent("\(choice.rawValue).png"),
                                    to: personalArtwork.appendingPathComponent("\(choice.rawValue).png"))
}
assert(MascotChoice.gopher.artworkURL(resources: artworkResources, personalDirectory: personalArtwork) == personalArtwork.appendingPathComponent("gopher.png"))
for choice in [MascotChoice.cat, .dog] {
    assert(choice.artworkURL(resources: artworkResources, personalDirectory: personalArtwork) == artworkResources.appendingPathComponent("\(choice.rawValue).png"),
           "A personal gopher must not affect other mascot choices")
}
try FileManager.default.removeItem(at: personalArtwork)
print("Personal gopher override and bundled mascot fallback unit checks passed.")

assert(normalizedTTY("s001") == "ttys001")
assert(normalizedTTY("/dev/ttys012") == "ttys012")
assert(normalizedTTY("ttys003") == "ttys003")
for invalid in ["?", "??", "", "ttys", "ttys001\"", "s001\nactivate", "s١"] {
    assert(normalizedTTY(invalid) == nil, "Rejected invalid or unsafe TTY: \(invalid)")
}

let fixture = """
10 1 ?? /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal
11 10 ttys001 /bin/zsh
12 11 ttys001 /opt/homebrew/bin/codex
13 12 ttys001 /opt/homebrew/lib/node_modules/@openai/codex/vendor/codex
20 1 ?? /Applications/iTerm.app/Contents/MacOS/iTerm2
21 20 s002 /bin/zsh
22 21 s002 /usr/local/bin/codex-aarch64-apple-darwin
30 1 ?? /Applications/ChatGPT.app/Contents/MacOS/ChatGPT
31 30 ?? /Applications/ChatGPT.app/Contents/Resources/codex
40 1 ttys003 /bin/zsh
41 40 ttys003 /some path with spaces/codex
42 40 ttys003 /usr/bin/not-codex
50 51 ttys004 /usr/local/bin/codex
51 50 ttys004 /bin/zsh
60 1 ttys005 /usr/local/bin/codex-pulse-server
malformed line
"""
let sessions = codexSessions(from: fixture)
assert(sessions.contains(CodexSession(tty: "ttys001", app: .terminal)))
assert(sessions.contains(CodexSession(tty: "ttys002", app: .iterm)))
assert(sessions.contains(CodexSession(tty: "ttys003", app: nil)))
assert(sessions.contains(CodexSession(tty: "ttys004", app: nil)))
assert(sessions.count == 4, "Ignore unrelated executables and desktop/background processes")
assert(sessions.filter { $0.tty == "ttys001" }.count == 1, "Nested Codex processes should give one entry")
assert(codexSessions(from: "").isEmpty)
assert(codexSessions(from: "1 0 ?? /usr/bin/codex").isEmpty, "Desktop/background processes have no terminal")
assert(sessions.map(\.tty) == sessions.map(\.tty).sorted())
print("Session parser unit checks passed.")

let original = CGRect(x: -100, y: 300, width: 100, height: 200)
let larger = resizedMascotFrame(original, height: 400, aspectRatio: 0.5)
assert(larger.size == CGSize(width: 200, height: 400))
assert(larger.midX == original.midX && larger.midY == original.midY, "Menu resizing preserves the center")
let anchor = CGPoint(x: 0.2, y: 0.8)
let anchored = resizedMascotFrame(original, height: 100, aspectRatio: 0.5, anchor: anchor)
assert(anchored.minX + anchored.width * anchor.x == original.minX + original.width * anchor.x)
assert(anchored.minY + anchored.height * anchor.y == original.minY + original.height * anchor.y,
       "Scrolling keeps the point under the pointer stationary, even on a screen with negative coordinates")
assert(resizedMascotFrame(original, height: -10, aspectRatio: 0.5).height == 64)
assert(resizedMascotFrame(original, height: 10000, aspectRatio: 0.5).height == 1200)
assert(resizedMascotFrame(original, height: .nan, aspectRatio: 0.5) == original)
assert(resizedMascotFrame(original, height: 140, aspectRatio: 0) == original)
print("Resize geometry unit checks passed.")

assert(DatabaseKubectl.contexts(from: "stage\ndev\nstage\n\ncluster with spaces\n") == ["cluster with spaces", "dev", "stage"])
let contextSnapshot = KubernetesContextSnapshot(output: "stage\nstage\ndev\nstage\ncluster with spaces\n")
assert(contextSnapshot.current == "stage")
assert(contextSnapshot.contexts == ["cluster with spaces", "dev", "stage"])
let noCurrentContext = KubernetesContextSnapshot(output: "\ndev\nstage\n")
assert(noCurrentContext.current == nil && noCurrentContext.contexts == ["dev", "stage"], "An unset current context must not consume the first available context")
for emptyConfig in ["", "\n"] {
    let snapshot = KubernetesContextSnapshot(output: emptyConfig)
    assert(snapshot.current == nil && snapshot.contexts.isEmpty)
}
assert(KubernetesContextSnapshot(output: "removed\ndev\n").current == "removed", "Display the actual value even if its context was removed")
for name in ["cluster with spaces", "prod; $(echo not-a-shell-command)", "--kubeconfig=/tmp/other", "кибер-клъстер"] {
    assert(KubernetesContextSnapshot.useArguments(context: name) == ["config", "use-context", "--", name],
           "A context stays one literal positional argument, including names resembling flags")
    let snapshot = KubernetesContextSnapshot(output: "\(name)\n\(name)\n")
    assert(snapshot.current == name && snapshot.contexts == [name])
}
let contextController = DatabaseForwarder()
contextController.useContext("unknown") { _ in assertionFailure("An undiscovered context must not start a command") }
assert(!contextController.isBusy && contextController.switchingContext == nil)
contextController.shutdown()
contextController.refreshContexts()
assert(!contextController.loadingContexts, "Shutdown must not start a new kubeconfig read")
print("Kubernetes current-context parsing, empty config, literal selection arguments, and inactive lifecycle unit checks passed.")
let literalContext = "prod; $(echo not-a-shell-command)"
let prefixTarget = DatabaseTarget(name: "Database", namespace: "databases", context: nil, resource: nil,
                                  podNamePrefix: "database-", localPort: 15432, remotePort: 5432)
try prefixTarget.validate()
let exampleConfiguration = try Configuration.load(from: URL(fileURLWithPath: "examples/config.json"))
assert(exampleConfiguration.databaseTargets.count == 2)
assert(exampleConfiguration.targets(for: "some-cluster").map(\.name) == ["PostgreSQL"])
assert(exampleConfiguration.targets(for: "my-dev-cluster").map(\.name) == ["PostgreSQL", "MySQL development"])
let serviceTarget = exampleConfiguration.databaseTargets[1]
let serviceArgs = DatabaseKubectl.forwardArguments(context: "my-dev-cluster", target: serviceTarget, resource: serviceTarget.resource!)
assert(serviceArgs.contains("service/mysql") && serviceArgs.contains("--namespace=databases") && serviceArgs.contains("3307:3306"))
assert(serviceArgs.contains("--context=my-dev-cluster") && serviceArgs.contains("--address=127.0.0.1"))
let privateConfiguration = Configuration(kubeconfig: "~/custom cluster/config", databaseTargets: [prefixTarget])
try privateConfiguration.validate()
assert(privateConfiguration.kubeconfigPath == NSHomeDirectory() + "/custom cluster/config")
let configRoundTrip = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(privateConfiguration))
assert(configRoundTrip == privateConfiguration)
let isolatedConfig = FileManager.default.temporaryDirectory.appendingPathComponent("gopher-unit-\(UUID().uuidString).json")
let freshConfiguration = try Configuration.load(from: isolatedConfig)
assert(freshConfiguration == Configuration(), "New installations have no database targets")
try JSONEncoder().encode(privateConfiguration).write(to: isolatedConfig)
let loadedPrivateConfiguration = try Configuration.load(from: isolatedConfig)
assert(loadedPrivateConfiguration == privateConfiguration)
try Data("{invalid json".utf8).write(to: isolatedConfig)
do { _ = try Configuration.load(from: isolatedConfig); assertionFailure("Invalid JSON must not silently reset settings") } catch { }
try FileManager.default.removeItem(at: isolatedConfig)
for resource in ["service/postgres", "deployment/mysql", "pod/database-0", "pod/db.example"] {
    try DatabaseTarget(name: "Test", namespace: "default", context: "my-cluster", resource: resource,
                       podNamePrefix: nil, localPort: 1, remotePort: 65535).validate()
}
for (name, namespace, context, resource, prefix, local, remote) in [
    ("", "default", nil, "service/db", nil, 5432, 5432),
    ("bad\nname", "default", nil, "service/db", nil, 5432, 5432),
    ("DB", "--bad", nil, "service/db", nil, 5432, 5432),
    ("DB", "default\n", nil, "service/db", nil, 5432, 5432),
    ("DB", "default", "", "service/db", nil, 5432, 5432),
    ("DB", "default", "bad\ncontext", "service/db", nil, 5432, 5432),
    ("DB", "default", nil, "service/db", nil, 0, 5432),
    ("DB", "default", nil, "service/db", nil, 5432, 65536),
    ("DB", "default", nil, "--address=0.0.0.0", nil, 5432, 5432),
    ("DB", "default", nil, "service/../db", nil, 5432, 5432),
    ("DB", "default", nil, "service/$(bad)", nil, 5432, 5432),
    ("DB", "default", nil, "service/db\n", nil, 5432, 5432),
    ("DB", "default", nil, "service/db", "db-", 5432, 5432),
    ("DB", "default", nil, nil, nil, 5432, 5432),
    ("DB", "default", nil, nil, "", 5432, 5432),
    ("DB", "default", nil, nil, "db-\n", 5432, 5432),
    ("DB", "default", nil, nil, "--all", 5432, 5432)
] as [(String, String, String?, String?, String?, Int, Int)] {
    do {
        try DatabaseTarget(name: name, namespace: namespace, context: context, resource: resource,
                           podNamePrefix: prefix, localPort: local, remotePort: remote).validate()
        assertionFailure("Reject invalid target before any kubectl command")
    } catch { }
}
for config in [Configuration(kubeconfig: "relative/path"), Configuration(kubeconfig: "/a:/b"),
               Configuration(databaseTargets: [prefixTarget, prefixTarget])] {
    do { try config.validate(); assertionFailure("Reject invalid paths and duplicate names") } catch { }
}
let invalidConfiguration = Configuration(databaseTargets: [prefixTarget, prefixTarget])
let unconfiguredForwarder = DatabaseForwarder()
do { try unconfiguredForwarder.configure(invalidConfiguration); assertionFailure("Reject settings before any process is started") } catch { }
unconfiguredForwarder.start(context: "unknown", target: prefixTarget)
assert(!unconfiguredForwarder.isBusy && unconfiguredForwarder.configuration == Configuration())
print("Database settings, scoped targets, service arguments, private config round-trip, and input validation unit checks passed.")
let podArgs = DatabaseKubectl.podArguments(context: literalContext, target: prefixTarget)
let forwardArgs = DatabaseKubectl.forwardArguments(context: literalContext, target: prefixTarget, resource: "pod/database-a")
assert(podArgs.contains("--context=\(literalContext)") && forwardArgs.contains("--context=\(literalContext)"))
assert(!podArgs.contains("use-context") && !forwardArgs.contains("use-context"))
assert(forwardArgs.contains("--address=127.0.0.1") && forwardArgs.contains("15432:5432"))
assert(forwardArgs.contains("--namespace=databases") && forwardArgs.contains("pod/database-a"))

let podFixture = Data(#"""
{"items":[
  {"metadata":{"name":"database-a-terminating","deletionTimestamp":"2026-11-06T00:00:00Z"},"status":{"phase":"Running","conditions":[{"type":"Ready","status":"True"}]}},
  {"metadata":{"name":"database-a-pending"},"status":{"phase":"Pending"}},
  {"metadata":{"name":"database-a-not-ready"},"status":{"phase":"Running","conditions":[{"type":"Ready","status":"False"}]}},
  {"metadata":{"name":"database-z-ready"},"status":{"phase":"Running","conditions":[{"type":"Ready","status":"True"}]}},
  {"metadata":{"name":"database-b-ready"},"status":{"phase":"Running","conditions":[{"type":"Ready","status":"True"}]}},
  {"metadata":{"name":"database-$(invalid)"},"status":{"phase":"Running","conditions":[{"type":"Ready","status":"True"}]}},
  {"metadata":{"name":"another-service"},"status":{"phase":"Running","conditions":[{"type":"Ready","status":"True"}]}}
]}
"""#.utf8)
let selectedPod = try DatabaseKubectl.matchingPod(from: podFixture, prefix: "database-")
assert(selectedPod == "database-b-ready", "Prefer Ready, ignore terminating pods, choose deterministically")
let noReadyPods = Data(#"{"items":[{"metadata":{"name":"database-a"},"status":{"phase":"Running"}}]}"#.utf8)
let fallbackPod = try DatabaseKubectl.matchingPod(from: noReadyPods, prefix: "database-")
assert(fallbackPod == "database-a")
for invalid in [Data(#"{"items":[]}"#.utf8), Data("not JSON".utf8)] {
    do { _ = try DatabaseKubectl.matchingPod(from: invalid, prefix: "database-"); assertionFailure("Must reject missing/invalid pods") }
    catch { }
}

var forwardState = DatabaseForwardState()
let firstRequest = forwardState.begin(context: "dev", localPort: 5432)!
assert(forwardState.phase == .findingPod && forwardState.isBusy)
assert(forwardState.begin(context: "prod", localPort: 5432) == nil, "Never silently repoint a busy local database port")
assert(!forwardState.received("Forwarding from 127.0.0.1:5432 -> 5432", for: firstRequest), "Pod lookup is not a connected tunnel")
forwardState.stop()
assert(!forwardState.foundPod(for: firstRequest), "Cancel during lookup must never start a forward")
forwardState.finished(firstRequest, error: "terminated")
assert(forwardState.phase == .idle && forwardState.context == nil && forwardState.error == nil)
let secondRequest = forwardState.begin(context: "stage", localPort: 5432)!
assert(!forwardState.foundPod(for: firstRequest), "Ignore stale callbacks")
assert(forwardState.foundPod(for: secondRequest))
assert(!forwardState.received("Forwarding from 127.0.0.1:", for: secondRequest))
assert(forwardState.received("5432 -> 5432\n", for: secondRequest), "Readiness can arrive in split pipe reads")
assert(forwardState.phase == .forwarding)
forwardState.finished(firstRequest, error: "old error")
assert(forwardState.phase == .forwarding)
forwardState.finished(secondRequest, error: "connection lost")
assert(forwardState.phase == .failed && !forwardState.isBusy && forwardState.error == "connection lost")
let thirdRequest = forwardState.begin(context: "dev", localPort: 5432)!
assert(forwardState.foundPod(for: thirdRequest))
forwardState.stop()
assert(!forwardState.received("Forwarding from 127.0.0.1:5432 -> 5432\n", for: thirdRequest), "Readiness after cancellation must not reconnect")
forwardState.finished(thirdRequest, error: "terminated")
assert(forwardState.phase == .idle)
print("Database selection, literal arguments, readiness, cancellation, and stale-callback unit checks passed.")

var customPortState = DatabaseForwardState()
assert(customPortState.begin(context: "dev", localPort: 0) == nil)
let customRequest = customPortState.begin(context: "dev", localPort: 3307)!
assert(customPortState.foundPod(for: customRequest))
assert(!customPortState.received("Forwarding from 127.0.0.1:5432 -> 5432\n", for: customRequest))
assert(!customPortState.received("Forwarding from 127.0.0.1:33", for: customRequest))
assert(customPortState.received("07 -> 13306\n", for: customRequest), "A service can resolve to a different pod port; wait for the requested local listener")
print("Custom local port and service target-port readiness unit checks passed.")

// Exercise only an in-process pipe: no kubectl, cluster, child process, or network connection.
let commandPipe = Pipe()
let readiness = Data("Forwarding from 127.0.0.1:5432 -> 5432\n".utf8)
try commandPipe.fileHandleForWriting.write(contentsOf: readiness)
var commandRunning = true
var receivedOutput = Data()
try readKubectlPipe(commandPipe.fileHandleForReading, isRunning: { commandRunning }) {
    receivedOutput.append($0)
    commandRunning = false
}
assert(receivedOutput == readiness, "Read short output before EOF; return after exit even when a helper keeps the writer open")
try commandPipe.fileHandleForWriting.close()
print("Live-output pipe reader unit check passed.")

assert(FavouriteLinks.defaults.isEmpty, "Public installations must not include personal links")
let linkFixtures = ["My existing link": "https://example.com/#/route?path=%2Ffoo&params=",
                    "Another link": "https://example.org/path#"]
for address in linkFixtures.values {
    assert(FavouriteLinks.webURL(address)?.absoluteString == address, "Keep encoded paths, hash routes, empty parameters, and trailing # intact")
}
let addedLinks = try FavouriteLinks.adding(name: "  My link  ", address: "  https://example.com/#/route?path=%2Ffoo&params=  ", to: linkFixtures)
assert(addedLinks["My link"] == "https://example.com/#/route?path=%2Ffoo&params=")
assert(addedLinks.count == 3 && linkFixtures.allSatisfy { addedLinks[$0.key] == $0.value })
assert(FavouriteLinks.webURL("http://localhost:3000/page") != nil)
for invalid in ["javascript:alert(1)", "file:///etc/hosts", "mailto:someone@example.com", "/relative", "https://", "https://example.com/a b", "https://example.com/\npath"] {
    assert(FavouriteLinks.webURL(invalid) == nil, "Only complete web links can be launched")
}
for (name, address) in [("", "https://example.com"), ("bad\nname", "https://example.com"),
                        ("Invalid URL", "not a URL"), ("My existing link", "https://example.com")] {
    do { _ = try FavouriteLinks.adding(name: name, address: address, to: linkFixtures); assertionFailure("Invalid/duplicate links must not be saved") }
    catch { }
}
let encodedLinks = try PropertyListEncoder().encode(addedLinks)
let restoredLinks = try PropertyListDecoder().decode([String: String].self, from: encodedLinks)
assert(restoredLinks == addedLinks, "The name-to-URL dictionary round-trips through preference storage without altering URLs")
print("Favourite link validation, duplicate protection, exact URL preservation, and dictionary storage unit checks passed.")
