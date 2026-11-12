import AppKit
import QuartzCore

final class MascotPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class MascotButton: NSButton {
    private let artwork = CALayer()
    private var downEvent: NSEvent?
    private var startMouse = NSPoint.zero
    private var dragged = false
    var resize: ((CGFloat) -> Void)?

    func setArtwork(_ image: NSImage) {
        wantsLayer = true
        if artwork.superlayer == nil {
            layer?.addSublayer(artwork)
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateMotion),
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artwork.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        artwork.contentsGravity = .resizeAspect
        CATransaction.commit()
        needsLayout = true
        updateMotion()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artwork.frame = bounds.insetBy(dx: 3, dy: 4)
        CATransaction.commit()
    }

    @objc private func updateMotion() {
        artwork.removeAllAnimations()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let breathe = CABasicAnimation(keyPath: "transform.scale.y")
        breathe.fromValue = 1.0
        breathe.toValue = 1.018
        breathe.duration = 2.4
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        artwork.add(breathe, forKey: "breathe")
    }

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        startMouse = NSEvent.mouseLocation
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - startMouse.x
        let dy = mouse.y - startMouse.y
        guard !dragged, hypot(dx, dy) > 3, let downEvent else { return }
        dragged = true
        // Hand off to Window Server so dragging stays smooth across displays and Spaces.
        window?.performDrag(with: downEvent)
    }

    override func mouseUp(with event: NSEvent) {
        if !dragged { performClick(nil) }
        downEvent = nil
    }

    override func rightMouseDown(with event: NSEvent) { performClick(nil) }

    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase == [] else { return }
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.6 : 8)
        resize?(bounds.height + delta)
    }

    override func magnify(with event: NSEvent) { resize?(bounds.height * (1 + event.magnification)) }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: NSPanel!
    private var mascot: MascotButton!
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var sessions: [CodexSession] = []
    private var aspectRatio: CGFloat = 1
    private var selectedMascot = MascotChoice(savedValue: UserDefaults.standard.string(forKey: "SelectedMascot"))
    private let database = DatabaseForwarder()
    private let databaseMenu = NSMenu()
    private var databaseMenuItem: NSMenuItem?
    private let contextMenu = NSMenu()
    private var contextMenuItem: NSMenuItem?
    private var reportedDatabaseFailure: UUID?
    private var configurationError: String?
    private var quitting = false
    private var favouriteLinks = UserDefaults.standard.dictionary(forKey: "FavouriteLinks") as? [String: String] ?? FavouriteLinks.defaults

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: {
               $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
           }) {
            NSApp.terminate(nil)
            return
        }
        guard let image = loadArtwork(selectedMascot) else {
            showError("The \(selectedMascot.title) image could not be loaded. Check your artwork files or rebuild the app with build.sh.")
            NSApp.terminate(nil)
            return
        }
        NSApp.applicationIconImage = image
        menu.delegate = self

        aspectRatio = image.size.width / image.size.height
        panel = MascotPanel(contentRect: NSRect(x: 0, y: 0, width: defaultMascotHeight * aspectRatio, height: defaultMascotHeight),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.title = "Docksy"
        mascot = MascotButton(frame: NSRect(origin: .zero, size: panel.frame.size))
        mascot.setArtwork(image)
        mascot.resize = { [weak self] height in self?.resizeMascot(height: height, aroundMouse: true) }
        mascot.isBordered = false
        mascot.title = ""
        mascot.target = self
        mascot.action = #selector(showMenu)
        mascot.toolTip = "Docksy — click for apps, drag to move, scroll or pinch to resize"
        mascot.setAccessibilityLabel("Docksy \(selectedMascot.title) launcher")
        mascot.setAccessibilityHelp("Open the menu for ChatGPT or a running Codex terminal. Drag to reposition. Scroll, pinch, or use the Size menu to resize.")
        panel.contentView = mascot
        if !panel.setFrameUsingName("USRVPosition") { resetPosition() }
        let savedHeight = UserDefaults.standard.object(forKey: "MascotHeight") as? Double
        resizeMascot(height: savedHeight.map { CGFloat($0) } ?? defaultMascotHeight)
        keepVisible()
        panel.orderFrontRegardless()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusArtwork(image)
        statusItem.button?.toolTip = "Docksy"
        statusItem.menu = menu
        databaseMenu.autoenablesItems = false
        contextMenu.autoenablesItems = false
        database.onChange = { [weak self] in self?.databaseChanged() }
        reloadConfiguration()
        NotificationCenter.default.addObserver(self, selector: #selector(keepVisible),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(savePosition),
                                               name: NSWindow.didMoveNotification, object: panel)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add("Docksy \(selectedMascot.title)", to: menu, action: nil)
        menu.addItem(.separator())
        add("Open ChatGPT", to: menu, action: #selector(openChatGPT), icon: "bubble.left.and.bubble.right")
        do {
            sessions = try discoverSessions()
            if sessions.count == 1 {
                let item = add("Open Codex terminal", to: menu, action: #selector(openSession(_:)), icon: "terminal")
                item.tag = 0
            } else if !sessions.isEmpty {
                let item = add("Codex terminals (\(sessions.count))", to: menu, action: nil, icon: "terminal")
                let submenu = NSMenu()
                for (index, session) in sessions.enumerated() {
                    let child = add(session.title, to: submenu, action: #selector(openSession(_:)))
                    child.tag = index
                }
                item.submenu = submenu
            } else {
                add("No running Codex terminals found", to: menu, action: nil, icon: "terminal")
            }
        } catch {
            sessions = []
            add("Couldn’t read Codex sessions", to: menu, action: nil)
        }
        menu.addItem(.separator())
        contextMenuItem = add("Kubernetes context", to: menu, action: nil, icon: "server.rack")
        contextMenuItem?.submenu = contextMenu
        databaseMenuItem = add(databaseMenuTitle, to: menu, action: nil, icon: "network")
        databaseMenuItem?.submenu = databaseMenu
        if configurationError == nil { database.refreshContexts() }
        updateContextMenu()
        updateDatabaseMenu()
        let linksMenu = NSMenu()
        for name in favouriteLinks.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            let item = add(name, to: linksMenu, action: #selector(openFavouriteLink(_:)))
            item.representedObject = favouriteLinks[name]
            item.toolTip = favouriteLinks[name]
        }
        linksMenu.addItem(.separator())
        add("Add link…", to: linksMenu, action: #selector(addFavouriteLink))
        add("Favourite links", to: menu, action: nil, icon: "star").submenu = linksMenu
        menu.addItem(.separator())
        let mascotMenu = NSMenu()
        for choice in MascotChoice.allCases {
            let item = add(choice.title, to: mascotMenu, action: #selector(changeMascot(_:)))
            item.representedObject = choice.rawValue
            item.state = choice == selectedMascot ? .on : .off
        }
        add("Mascot", to: menu, action: nil, icon: "pawprint").submenu = mascotMenu
        add("Drag to move · Scroll or pinch to resize", to: menu, action: nil)
        let sizeMenu = NSMenu()
        add("Smaller", to: sizeMenu, action: #selector(changeSize(_:))).tag = -1
        add("Larger", to: sizeMenu, action: #selector(changeSize(_:))).tag = 1
        add("Reset size", to: sizeMenu, action: #selector(changeSize(_:))).tag = 0
        add("Size", to: menu, action: nil, icon: "arrow.up.left.and.arrow.down.right").submenu = sizeMenu
        add("Reset mascot position", to: menu, action: #selector(resetPosition))
        add("About Docksy", to: menu, action: #selector(showAbout))
        add("Quit Docksy", to: menu, action: #selector(quit))
    }

    @discardableResult
    private func add(_ title: String, to menu: NSMenu, action: Selector?, icon: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if menu === databaseMenu || menu === contextMenu { item.isEnabled = action != nil }
        if let icon { item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil) }
        menu.addItem(item)
        return item
    }

    @objc private func showMenu() {
        menu.popUp(positioning: nil, at: NSPoint(x: mascot.bounds.midX, y: mascot.bounds.midY), in: mascot)
    }

    private func loadArtwork(_ choice: MascotChoice) -> NSImage? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        return NSImage(contentsOf: choice.artworkURL(resources: resources,
            personalDirectory: Configuration.fileURL.deletingLastPathComponent()))
    }

    private func updateStatusArtwork(_ image: NSImage) {
        let smallImage = image.copy() as! NSImage
        let scale = min(18 / image.size.width, 20 / image.size.height)
        smallImage.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        statusItem.button?.image = smallImage
        statusItem.button?.setAccessibilityLabel("Docksy \(selectedMascot.title) menu")
    }

    @objc private func changeMascot(_ item: NSMenuItem) {
        guard let value = item.representedObject as? String,
              let choice = MascotChoice(rawValue: value), choice != selectedMascot else { return }
        guard let image = loadArtwork(choice) else {
            showError("The \(choice.title) image could not be loaded. Check your artwork files or rebuild the app with build.sh.")
            return
        }
        selectedMascot = choice
        mascot.setArtwork(image)
        mascot.setAccessibilityLabel("Docksy \(choice.title) launcher")
        NSApp.applicationIconImage = image
        updateStatusArtwork(image)
        aspectRatio = image.size.width / image.size.height
        resizeMascot(height: panel.frame.height)
        keepVisible()
        UserDefaults.standard.set(choice.rawValue, forKey: "SelectedMascot")
    }

    @objc private func openFavouriteLink(_ item: NSMenuItem) {
        guard let address = item.representedObject as? String, let url = FavouriteLinks.webURL(address) else {
            showError("This favourite does not contain a valid http:// or https:// URL.")
            return
        }
        if !NSWorkspace.shared.open(url) { showError("macOS could not open this link in your default browser.") }
    }

    @objc private func addFavouriteLink() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Add favourite link"
        alert.informativeText = "Save a name and URL. Links open in your default browser."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 112))
        let nameLabel = NSTextField(labelWithString: "Name")
        nameLabel.frame = NSRect(x: 0, y: 92, width: 460, height: 18)
        let nameField = NSTextField(frame: NSRect(x: 0, y: 64, width: 460, height: 24))
        nameField.placeholderString = "My favourite link"
        nameField.setAccessibilityLabel("Link name")
        let urlLabel = NSTextField(labelWithString: "URL")
        urlLabel.frame = NSRect(x: 0, y: 34, width: 460, height: 18)
        let urlField = NSTextField(frame: NSRect(x: 0, y: 6, width: 460, height: 24))
        urlField.placeholderString = "https://…"
        urlField.setAccessibilityLabel("Link URL")
        nameField.nextKeyView = urlField
        for view in [nameLabel, nameField, urlLabel, urlField] { fields.addSubview(view) }
        alert.accessoryView = fields
        alert.window.initialFirstResponder = nameField
        while alert.runModal() == .alertFirstButtonReturn {
            do {
                favouriteLinks = try FavouriteLinks.adding(name: nameField.stringValue, address: urlField.stringValue, to: favouriteLinks)
                UserDefaults.standard.set(favouriteLinks, forKey: "FavouriteLinks")
                return
            } catch { alert.informativeText = error.localizedDescription }
        }
    }

    private func updateContextMenu() {
        contextMenuItem?.title = database.switchingContext != nil ? "Kubernetes context · Switching…" : "Kubernetes context"
        contextMenu.removeAllItems()
        add("Current: \(database.currentContext ?? "None")", to: contextMenu, action: nil)
        add("Changes the default context used by kubectl", to: contextMenu, action: nil)
        if let switching = database.switchingContext {
            add("Switching to \(switching)…", to: contextMenu, action: nil)
        }
        contextMenu.addItem(.separator())
        if let error = configurationError {
            add("Settings error…", to: contextMenu, action: #selector(showDatabaseError(_:))).representedObject = error
        }
        if let error = database.contextsError {
            add("Show error…", to: contextMenu, action: #selector(showDatabaseError(_:))).representedObject = error
        }
        if database.loadingContexts {
            add("Loading contexts…", to: contextMenu, action: nil)
        } else if database.contexts.isEmpty {
            add("No Kubernetes contexts available", to: contextMenu, action: nil)
        }
        for context in database.contexts {
            let item = add(context, to: contextMenu, action: #selector(useContext(_:)))
            item.representedObject = context
            item.state = context == database.currentContext ? .on : .off
            item.isEnabled = configurationError == nil && !database.loadingContexts && database.switchingContext == nil
        }
        contextMenu.addItem(.separator())
        let refresh = add("Refresh contexts", to: contextMenu, action: #selector(refreshDatabaseContexts))
        refresh.isEnabled = configurationError == nil && !database.loadingContexts && database.switchingContext == nil
        addConfigurationItems(to: contextMenu)
    }

    @objc private func useContext(_ item: NSMenuItem) {
        guard configurationError == nil, let context = item.representedObject as? String else { return }
        database.useContext(context) { [weak self] error in
            if let error { self?.showError("Could not switch Kubernetes context to \(context).\n\n" + String(error.suffix(2000))) }
        }
    }

    private var databaseMenuTitle: String {
        switch database.state.phase {
        case .forwarding: return "Database port-forward · Connected"
        case .findingPod, .starting: return "Database port-forward · Connecting…"
        case .stopping: return "Database port-forward · Stopping…"
        case .failed: return "Database port-forward · Failed"
        case .idle: return "Database port-forward"
        }
    }

    private func updateDatabaseMenu() {
        databaseMenuItem?.title = databaseMenuTitle
        databaseMenu.removeAllItems()
        if let target = database.target {
            add("\(target.name) at \(target.endpoint)", to: databaseMenu, action: nil)
        } else if database.configuration.databaseTargets.count == 1, let target = database.configuration.databaseTargets.first {
            add("\(target.name) at \(target.endpoint)", to: databaseMenu, action: nil)
        } else {
            add("Choose a context and database", to: databaseMenu, action: nil)
        }
        if let context = database.state.context {
            add("Cluster: \(context)", to: databaseMenu, action: nil)
        }
        if database.state.isBusy {
            let stopping = database.state.phase == .stopping
            let title = stopping ? "Stopping…" : (database.state.phase == .forwarding ? "Stop port-forward" : "Cancel connection")
            add(title, to: databaseMenu, action: stopping ? nil : #selector(stopDatabase))
            add("Stop the current forward to choose another cluster", to: databaseMenu, action: nil)
            databaseMenu.addItem(.separator())
        }
        if let error = configurationError ?? database.contextsError ?? database.state.error {
            add("Show error…", to: databaseMenu, action: #selector(showDatabaseError(_:))).representedObject = error
            databaseMenu.addItem(.separator())
        }
        if database.contexts.isEmpty {
            add(database.loadingContexts ? "Loading clusters…" : "No Kubernetes contexts available", to: databaseMenu, action: nil)
        }
        if database.configuration.databaseTargets.isEmpty {
            add("No database targets — open Settings… to add one", to: databaseMenu, action: nil)
        }
        for context in database.contexts {
            let targets = database.configuration.targets(for: context)
            guard !targets.isEmpty else { continue }
            let destination: NSMenu
            if targets.count == 1 {
                destination = databaseMenu
            } else {
                destination = NSMenu()
                destination.autoenablesItems = false
                let parent = add(context, to: databaseMenu, action: nil)
                parent.submenu = destination
                parent.isEnabled = true
            }
            for target in targets {
                let title = targets.count == 1 ? context : "\(target.name) · \(target.endpoint)"
                let item = add(title, to: destination, action: #selector(startDatabase(_:)))
                item.representedObject = ["context": context, "target": target.name]
                item.toolTip = "\(target.namespace)/\(target.resource ?? target.podNamePrefix ?? "") · \(target.localPort):\(target.remotePort)"
                item.isEnabled = configurationError == nil && !database.isBusy
                if database.state.isBusy && database.state.context == context && database.target == target { item.state = .on }
            }
        }
        databaseMenu.addItem(.separator())
        add("Refresh clusters", to: databaseMenu, action: #selector(refreshDatabaseContexts)).isEnabled = configurationError == nil
        addConfigurationItems(to: databaseMenu)
    }

    private func addConfigurationItems(to menu: NSMenu) {
        menu.addItem(.separator())
        add("Settings…", to: menu, action: #selector(openConfiguration))
        add("Reload settings", to: menu, action: #selector(reloadConfiguration)).isEnabled = database.canConfigure
    }

    @objc private func openConfiguration() {
        do {
            let url = Configuration.fileURL
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                guard let example = Bundle.main.url(forResource: "config.example", withExtension: "json") else {
                    throw Configuration.error("The example settings are missing. Rebuild the app.")
                }
                try Data(contentsOf: example).write(to: url, options: .withoutOverwriting)
            }
            guard let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
                throw Configuration.error("Open \(url.path) in a text editor, save it, then choose Reload settings.")
            }
            NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { DispatchQueue.main.async { self.showError(error.localizedDescription) } }
            }
        } catch { showError(error.localizedDescription) }
    }

    @objc private func reloadConfiguration() {
        do {
            let configuration = try Configuration.load(from: Configuration.fileURL)
            try database.configure(configuration)
            configurationError = nil
        } catch {
            configurationError = error.localizedDescription
            showError("Could not load settings. Fix config.json, then choose Reload settings.\n\n" + error.localizedDescription)
        }
        updateDatabaseMenu()
        updateContextMenu()
    }

    private func databaseChanged() {
        if quitting {
            if !database.isBusy { NSApp.reply(toApplicationShouldTerminate: true) }
            return
        }
        updateDatabaseMenu()
        updateContextMenu()
        statusItem.button?.toolTip = database.state.isBusy
            ? "Docksy · \(database.state.context ?? "") · \(databaseMenuTitle)" : "Docksy"
        if database.state.phase == .failed, reportedDatabaseFailure != database.state.request {
            reportedDatabaseFailure = database.state.request
            let request = database.state.request
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.quitting, self.database.state.request == request,
                      self.database.state.phase == .failed else { return }
                self.showError("Database port-forward failed for \(self.database.state.context ?? "the selected cluster").\n\n" +
                               String((self.database.state.error ?? "Unknown error.").suffix(2000)))
            }
        }
    }

    @objc private func startDatabase(_ item: NSMenuItem) {
        guard configurationError == nil, let selection = item.representedObject as? [String: String],
              let context = selection["context"],
              let target = database.configuration.targets(for: context).first(where: { $0.name == selection["target"] }) else { return }
        database.start(context: context, target: target)
    }

    @objc private func stopDatabase() { database.stop() }
    @objc private func refreshDatabaseContexts() {
        if configurationError == nil { database.refreshContexts() }
        updateDatabaseMenu()
        updateContextMenu()
    }
    @objc private func showDatabaseError(_ item: NSMenuItem) {
        if let error = item.representedObject as? String { showError(String(error.suffix(2000))) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitting = true
        database.shutdown()
        return database.isBusy ? .terminateLater : .terminateNow
    }

    @objc private func openChatGPT() {
        // The installed ChatGPT app currently uses com.openai.codex as its bundle ID.
        let candidates = ["/Applications/ChatGPT.app", NSHomeDirectory() + "/Applications/ChatGPT.app"]
        guard let url = candidates.map({ URL(fileURLWithPath: $0) }).first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.chat") else {
            showError("ChatGPT.app was not found in Applications.")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { DispatchQueue.main.async { self.showError(error.localizedDescription) } }
        }
    }

    @objc private func openSession(_ item: NSMenuItem) {
        guard sessions.indices.contains(item.tag) else { return }
        let session = sessions[item.tag]
        guard normalizedTTY(session.tty) == session.tty else { return }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let candidates = session.app.map { [$0] } ?? TerminalApp.allCases
        var errors: [String] = []
        for app in candidates where running.contains(app.rawValue) {
            guard let url = Bundle.main.url(forResource: app == .terminal ? "Terminal" : "iTerm", withExtension: "applescript"),
                  let source = try? String(contentsOf: url, encoding: .utf8),
                  let script = NSAppleScript(source: "set wantedTTY to \"/dev/\(session.tty)\"\n" + source) else {
                errors.append("The \(app.name) launcher script is missing.")
                continue
            }
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if let error {
                if error[NSAppleScript.errorNumber] as? Int == -1743 {
                    errors.append("Allow Docksy to control \(app.name) in System Settings → Privacy & Security → Automation.")
                } else {
                    errors.append(error[NSAppleScript.errorMessage] as? String ?? "Could not focus \(app.name).")
                }
            } else if result.booleanValue { return }
        }
        showError(errors.isEmpty
                  ? "This Codex session is no longer available in Terminal or iTerm2. Open the menu again to refresh. Sessions inside tmux, SSH, or an editor’s terminal cannot be selected directly."
                  : errors.joined(separator: "\n\n"))
    }

    @objc private func resetPosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: area.maxX - panel.frame.width - 24, y: area.minY + 28))
        panel.saveFrame(usingName: "USRVPosition")
    }

    private func resizeMascot(height: CGFloat, aroundMouse: Bool = false) {
        var anchor = CGPoint(x: 0.5, y: 0.5)
        let mouse = NSEvent.mouseLocation
        if aroundMouse, panel.frame.contains(mouse) {
            anchor = CGPoint(x: (mouse.x - panel.frame.minX) / panel.frame.width,
                             y: (mouse.y - panel.frame.minY) / panel.frame.height)
        }
        panel.setFrame(resizedMascotFrame(panel.frame, height: height, aspectRatio: aspectRatio, anchor: anchor), display: true)
        UserDefaults.standard.set(Double(panel.frame.height), forKey: "MascotHeight")
        savePosition()
    }

    @objc private func changeSize(_ item: NSMenuItem) {
        let height = item.tag == 0 ? defaultMascotHeight : panel.frame.height * (item.tag > 0 ? 1.15 : 1 / 1.15)
        resizeMascot(height: height)
    }

    @objc private func savePosition() { panel.saveFrame(usingName: "USRVPosition") }

    @objc private func keepVisible() {
        if !NSScreen.screens.contains(where: { $0.frame.intersects(panel.frame) }) { resetPosition() }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Docksy"
        alert.informativeText = "A desktop mascot and Kubernetes helper. Code: MIT License.\n\nGo gopher design by Renée French, CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). This app’s gopher is an AI-generated adaptation with a Docksy sign.\n\nhttps://go.dev/blog/gopher"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Docksy"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
