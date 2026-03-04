import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - UI
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var shortcutMenuItem: NSMenuItem!
    private var historyMenu: NSMenu!

    // Choice menus
    private var langMenu: NSMenu!
    private var modeMenu: NSMenu!
    private var modelMenu: NSMenu!
    private var silenceMenu: NSMenu!
    private var maxMenu: NSMenu!
    private var outputMenu: NSMenu!

    // Toggle options
    private var autoSubmitItem: NSMenuItem!
    private var streamingPasteItem: NSMenuItem!
    private var postProcessItem: NSMenuItem!

    // MARK: - Managers
    private var cfg = ConfigManager.load()
    private let whisperManager = WhisperManager()
    private let hotkeyManager = HotkeyManager()
    private let audioRecorder = AudioRecorder()
    private let beep = BeepPlayer()

    // MARK: - State
    private enum AppState { case idle, recording, processing, error }
    private var state: AppState = .idle
    private var isRecording = false
    private var recStartTime: Date?
    private var recTimer: Timer?
    private var maxTimer: Timer?
    private var history: [String] = []
    private let historyLimit = 5

    // MARK: - Lookup tables
    private let languages: [(label: String, code: String)] = [
        ("English", "en"), ("Czech", "cs"),
    ]
    private let modes: [(label: String, code: String)] = [
        ("Toggle", "toggle"), ("Push to talk", "push_to_talk"),
    ]
    private let models: [(label: String, code: String)] = [
        ("tiny", "tiny"), ("base", "base"), ("small", "small"),
        ("medium", "medium"), ("large-v3", "large-v3"),
    ]
    private let silenceOptions: [(label: String, value: Double)] = [
        ("Off", 0), ("5 seconds", 5), ("10 seconds", 10),
        ("20 seconds", 20), ("30 seconds", 30),
    ]
    private let maxOptions: [(label: String, value: Double)] = [
        ("1 minute", 60), ("2 minutes", 120), ("5 minutes", 300),
        ("10 minutes", 600), ("Unlimited", 0),
    ]
    private let outputModes: [(label: String, code: String)] = [
        ("Paste  (Cmd+V)", "paste"), ("Type  (keystroke)", "type"),
        ("Clipboard only", "clipboard"),
    ]

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "TranscriptWhatYouHear")
            button.image?.isTemplate = true
        }

        buildMenu()
        statusItem.menu = menu

        // Wire managers
        whisperManager.onProgress = { [weak self] msg in
            self?.statusMenuItem.title = msg
        }

        audioRecorder.onAutoStop = { [weak self] in
            DispatchQueue.main.async { self?.stopRecording() }
        }

        hotkeyManager.onKeyDown = { [weak self] in
            DispatchQueue.main.async { self?.onHotkeyDown() }
        }
        hotkeyManager.onKeyUp = { [weak self] in
            DispatchQueue.main.async { self?.onHotkeyUp() }
        }

        // Start
        hotkeyManager.register(shortcut: cfg.hotkey)
        Log.info("Starting — model=\(cfg.modelSize) hotkey=\(cfg.hotkey)")

        statusMenuItem.title = "Loading Whisper model…"
        whisperManager.loadModel(cfg.modelSize) { [weak self] result in
            switch result {
            case .success:
                self?.setReady()
            case .failure(let error):
                self?.statusMenuItem.title = "Model error: \(error.localizedDescription)"
                self?.setState(.error)
            }
        }
    }

    // MARK: - Menu Construction

    private func buildMenu() {
        menu.removeAllItems()

        let hk = HotkeyManager.displayString(for: cfg.hotkey)

        statusMenuItem = NSMenuItem(title: "Loading Whisper model…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        toggleMenuItem = NSMenuItem(title: "⏺  Start recording  \(hk)", action: #selector(toggleRecording), keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        menu.addItem(.separator())

        // Recording submenu
        let recItem = NSMenuItem(title: "Recording", action: nil, keyEquivalent: "")
        let recMenu = NSMenu()

        langMenu = buildChoiceMenu("Language", items: languages.map { ($0.label, $0.code) }, current: cfg.language, action: #selector(setLanguage(_:)))
        recMenu.addItem(withSubmenu("Language", menu: langMenu))

        modeMenu = buildChoiceMenu("Mode", items: modes.map { ($0.label, $0.code) }, current: cfg.mode, action: #selector(setMode(_:)))
        recMenu.addItem(withSubmenu("Mode", menu: modeMenu))

        modelMenu = buildChoiceMenu("Model", items: models.map { ($0.label, $0.code) }, current: cfg.modelSize, action: #selector(setModel(_:)))
        recMenu.addItem(withSubmenu("Model", menu: modelMenu))

        recMenu.addItem(.separator())

        silenceMenu = buildChoiceMenu("Silence auto-stop", items: silenceOptions.map { ($0.label, String($0.value)) }, current: String(cfg.silenceTimeout), action: #selector(setSilence(_:)))
        recMenu.addItem(withSubmenu("Silence auto-stop", menu: silenceMenu))

        maxMenu = buildChoiceMenu("Max duration", items: maxOptions.map { ($0.label, String($0.value)) }, current: String(cfg.maxDuration), action: #selector(setMaxDuration(_:)))
        recMenu.addItem(withSubmenu("Max duration", menu: maxMenu))

        recMenu.addItem(.separator())

        postProcessItem = NSMenuItem(title: "Post-process text", action: #selector(togglePostProcess), keyEquivalent: "")
        postProcessItem.target = self
        postProcessItem.state = cfg.postProcess ? .on : .off
        recMenu.addItem(postProcessItem)

        let calibrateItem = NSMenuItem(title: "Calibrate noise…", action: #selector(calibrateNoise), keyEquivalent: "")
        calibrateItem.target = self
        recMenu.addItem(calibrateItem)

        recItem.submenu = recMenu
        menu.addItem(recItem)

        // Output submenu
        let outItem = NSMenuItem(title: "Output", action: nil, keyEquivalent: "")
        outputMenu = NSMenu()
        for om in outputModes {
            let item = NSMenuItem(title: om.label, action: #selector(setOutput(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = om.code
            item.state = om.code == cfg.outputMode ? .on : .off
            outputMenu.addItem(item)
        }
        outputMenu.addItem(.separator())

        autoSubmitItem = NSMenuItem(title: "Auto-submit  (Enter after paste)", action: #selector(toggleAutoSubmit), keyEquivalent: "")
        autoSubmitItem.target = self
        autoSubmitItem.state = cfg.autoSubmit ? .on : .off
        outputMenu.addItem(autoSubmitItem)

        streamingPasteItem = NSMenuItem(title: "Streaming paste", action: #selector(toggleStreamingPaste), keyEquivalent: "")
        streamingPasteItem.target = self
        streamingPasteItem.state = cfg.streamingPaste ? .on : .off
        outputMenu.addItem(streamingPasteItem)

        outItem.submenu = outputMenu
        menu.addItem(outItem)

        menu.addItem(.separator())

        shortcutMenuItem = NSMenuItem(title: "Set shortcut…  \(hk)", action: #selector(setShortcut), keyEquivalent: "")
        shortcutMenuItem.target = self
        menu.addItem(shortcutMenuItem)

        menu.addItem(.separator())

        // History
        let histItem = NSMenuItem(title: "Recent transcriptions", action: nil, keyEquivalent: "")
        historyMenu = NSMenu()
        let placeholder = NSMenuItem(title: "(none yet)", action: nil, keyEquivalent: "")
        placeholder.isEnabled = false
        historyMenu.addItem(placeholder)
        histItem.submenu = historyMenu
        menu.addItem(histItem)

        menu.addItem(.separator())

        let helpItem = NSMenuItem(title: "Help…", action: #selector(openHelp), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)

        let logItem = NSMenuItem(title: "Open log", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Menu Helpers

    private func buildChoiceMenu(_ title: String, items: [(label: String, value: String)],
                                  current: String, action: Selector) -> NSMenu {
        let sub = NSMenu()
        for item in items {
            let mi = NSMenuItem(title: item.label, action: action, keyEquivalent: "")
            mi.target = self
            mi.representedObject = item.value
            mi.state = item.value == current ? .on : .off
            sub.addItem(mi)
        }
        return sub
    }

    private func withSubmenu(_ title: String, menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func updateChoiceMenu(_ menu: NSMenu, selected value: String) {
        for item in menu.items {
            item.state = (item.representedObject as? String) == value ? .on : .off
        }
    }

    // MARK: - State

    private func setState(_ newState: AppState) {
        state = newState
        guard let button = statusItem.button else { return }

        switch newState {
        case .idle:
            let img = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
            img?.isTemplate = true
            button.image = img
        case .recording:
            let img = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: nil)
            img?.isTemplate = false
            // Tint red
            button.image = img
            button.contentTintColor = .systemRed
        case .processing:
            let img = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil)
            img?.isTemplate = true
            button.image = img
            button.contentTintColor = nil
        case .error:
            let img = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            img?.isTemplate = true
            button.image = img
            button.contentTintColor = nil
        }

        if newState != .recording {
            button.contentTintColor = nil
        }
    }

    private func setReady(_ note: String = "") {
        setState(.idle)
        let suffix = note.isEmpty ? "" : "  (\(note))"
        statusMenuItem.title = "Ready  (Whisper \(cfg.modelSize))\(suffix)"
    }

    // MARK: - Hotkey

    private func onHotkeyDown() {
        if cfg.mode == "push_to_talk" {
            if !isRecording { toggleRecording() }
        } else {
            toggleRecording()
        }
    }

    private func onHotkeyUp() {
        if cfg.mode == "push_to_talk" && isRecording {
            toggleRecording()
        }
    }

    // MARK: - Recording

    @objc private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard !whisperManager.isLoading else {
            showNotification("Model still loading — please wait.")
            return
        }

        isRecording = true
        recStartTime = Date()

        audioRecorder.silenceThreshold = cfg.silenceThreshold
        audioRecorder.silenceTimeout = cfg.silenceTimeout

        do {
            try audioRecorder.start()
        } catch {
            Log.error("Recording failed: \(error)")
            statusMenuItem.title = "Mic error: \(error.localizedDescription)"
            setState(.error)
            isRecording = false
            return
        }

        setState(.recording)
        let hk = HotkeyManager.displayString(for: cfg.hotkey)
        toggleMenuItem.title = "⏹  Stop recording  \(hk)"

        // Max duration timer
        if cfg.maxDuration > 0 {
            maxTimer = Timer.scheduledTimer(withTimeInterval: cfg.maxDuration, repeats: false) { [weak self] _ in
                Log.warning("Max duration reached — auto-stopping")
                self?.stopRecording()
            }
        }

        // Elapsed time display
        recTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.recStartTime else { return }
            let elapsed = Int(Date().timeIntervalSince(start))
            let m = elapsed / 60
            let s = elapsed % 60
            let hk = HotkeyManager.displayString(for: self.cfg.hotkey)
            self.statusMenuItem.title = "● \(m):\(String(format: "%02d", s))  — \(hk) to stop"
        }

        beep.beepStart()
        Log.info("Recording started (silence=\(cfg.silenceTimeout)s  max=\(cfg.maxDuration > 0 ? "\(Int(cfg.maxDuration))s" : "∞"))")
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        recTimer?.invalidate()
        recTimer = nil
        maxTimer?.invalidate()
        maxTimer = nil

        let samples = audioRecorder.stop()

        setState(.processing)
        statusMenuItem.title = "Transcribing…"
        let hk = HotkeyManager.displayString(for: cfg.hotkey)
        toggleMenuItem.title = "⏺  Start recording  \(hk)"

        beep.beepStop()
        let duration = Double(samples.count) / AudioRecorder.sampleRate
        Log.info("Recording stopped — ~\(String(format: "%.1f", duration)) s captured")

        transcribeAndPaste(samples: samples)
    }

    // MARK: - Transcription

    private func transcribeAndPaste(samples: [Float]) {
        guard !samples.isEmpty else {
            Log.warning("No audio captured")
            setReady("no audio")
            return
        }

        let lang = cfg.language
        let streaming = cfg.streamingPaste && cfg.outputMode != "clipboard"
        let postProcess = cfg.postProcess

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            Log.info("Transcribing — lang=\(lang)")

            var streamedParts: [String] = []
            var isFirst = true

            let onSegment: ((String) -> Void)? = streaming ? { segment in
                let processed = postProcess ? PostProcessor.process(segment) : segment
                if !processed.isEmpty {
                    let prefix = isFirst ? "" : " "
                    isFirst = false
                    OutputManager.output(prefix + processed, mode: self.cfg.outputMode)
                    streamedParts.append(processed)
                }
            } : nil

            guard let result = self.whisperManager.transcribe(
                samples: samples, language: lang,
                streaming: streaming, onSegment: onSegment
            ) else {
                DispatchQueue.main.async { self.setReady("transcription error") }
                return
            }

            let text: String
            if streaming {
                text = streamedParts.joined(separator: " ")
            } else {
                text = postProcess ? PostProcessor.process(result.text) : result.text
                if !text.isEmpty {
                    OutputManager.output(text, mode: self.cfg.outputMode)
                }
            }

            Log.info("Transcribed — lang=\(lang) text='\(text)'")

            DispatchQueue.main.async {
                if !text.isEmpty {
                    if self.cfg.autoSubmit && !streaming {
                        usleep(100_000)
                        OutputManager.sendReturn()
                    }
                    let preview = text.count <= 70 ? text : String(text.prefix(67)) + "…"
                    self.addToHistory(text)
                    self.statusMenuItem.title = "Pasted: \(preview)"
                    self.setState(.idle)
                    self.beep.beepDone()
                } else {
                    Log.warning("No speech detected")
                    self.setReady("no speech detected")
                }
            }
        }
    }

    // MARK: - Settings Callbacks

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        cfg.language = code
        ConfigManager.save(cfg)
        updateChoiceMenu(langMenu, selected: code)
        Log.info("Language → \(sender.title) (\(code))")
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        cfg.mode = code
        ConfigManager.save(cfg)
        updateChoiceMenu(modeMenu, selected: code)
        Log.info("Mode → \(code)")
    }

    @objc private func setModel(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String, code != cfg.modelSize else { return }
        cfg.modelSize = code
        ConfigManager.save(cfg)
        updateChoiceMenu(modelMenu, selected: code)

        setState(.processing)
        statusMenuItem.title = "Loading Whisper \(code)…"
        whisperManager.loadModel(code) { [weak self] result in
            switch result {
            case .success:
                self?.setReady()
            case .failure(let error):
                self?.statusMenuItem.title = "Model error: \(error.localizedDescription)"
                self?.setState(.error)
            }
        }
        Log.info("Switching model → \(code)")
    }

    @objc private func setOutput(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        cfg.outputMode = code
        ConfigManager.save(cfg)
        for item in outputMenu.items where item.representedObject is String {
            item.state = (item.representedObject as? String) == code ? .on : .off
        }
        Log.info("Output mode → \(code)")
    }

    @objc private func setSilence(_ sender: NSMenuItem) {
        guard let valStr = sender.representedObject as? String, let val = Double(valStr) else { return }
        cfg.silenceTimeout = val
        ConfigManager.save(cfg)
        updateChoiceMenu(silenceMenu, selected: valStr)
        Log.info("Silence timeout → \(val) s")
    }

    @objc private func setMaxDuration(_ sender: NSMenuItem) {
        guard let valStr = sender.representedObject as? String, let val = Double(valStr) else { return }
        cfg.maxDuration = val
        ConfigManager.save(cfg)
        updateChoiceMenu(maxMenu, selected: valStr)
        Log.info("Max duration → \(val) s")
    }

    @objc private func toggleAutoSubmit() {
        cfg.autoSubmit.toggle()
        autoSubmitItem.state = cfg.autoSubmit ? .on : .off
        ConfigManager.save(cfg)
        Log.info("Auto-submit → \(cfg.autoSubmit)")
    }

    @objc private func toggleStreamingPaste() {
        cfg.streamingPaste.toggle()
        streamingPasteItem.state = cfg.streamingPaste ? .on : .off
        ConfigManager.save(cfg)
        Log.info("Streaming paste → \(cfg.streamingPaste)")
    }

    @objc private func togglePostProcess() {
        cfg.postProcess.toggle()
        postProcessItem.state = cfg.postProcess ? .on : .off
        ConfigManager.save(cfg)
        Log.info("Post-process → \(cfg.postProcess)")
    }

    // MARK: - Shortcut

    @objc private func setShortcut() {
        let current = HotkeyManager.displayString(for: cfg.hotkey)
        let alert = NSAlert()
        alert.messageText = "Set Shortcut"
        alert.informativeText = "Current shortcut: \(current)\n\nClick OK, then press your new key combination\n(use at least one modifier key + one other key)."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        statusMenuItem.title = "Press your new shortcut now…"

        hotkeyManager.captureShortcut { [weak self] shortcut in
            guard let self = self else { return }
            if let shortcut = shortcut {
                self.cfg.hotkey = shortcut
                ConfigManager.save(self.cfg)

                let display = HotkeyManager.displayString(for: shortcut)
                self.toggleMenuItem.title = "⏺  Start recording  \(display)"
                self.shortcutMenuItem.title = "Set shortcut…  \(display)"
                self.hotkeyManager.register(shortcut: shortcut)
                self.setReady()
                self.showNotification("Shortcut set to \(display)")
                Log.info("Hotkey changed → \(shortcut)")
            } else {
                Log.warning("Shortcut capture timed out")
                self.setReady()
            }
        }
    }

    // MARK: - Calibration

    @objc private func calibrateNoise() {
        let alert = NSAlert()
        alert.messageText = "Noise Calibration"
        alert.informativeText = "Stay quiet for 2 seconds.\nClick Start when ready."
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        statusMenuItem.title = "Calibrating… stay quiet"

        audioRecorder.calibrate { [weak self] rms in
            guard let self = self else { return }
            let threshold = max(rms * 2.0, 0.004)
            let rounded = (threshold * 100_000).rounded() / 100_000
            self.cfg.silenceThreshold = rounded
            ConfigManager.save(self.cfg)
            self.setReady("threshold set to \(rounded)")
            self.showNotification("Calibrated. New silence threshold: \(rounded)")
            Log.info("Calibrated: ambient RMS=\(String(format: "%.5f", rms)) → threshold=\(String(format: "%.5f", rounded))")
        }
    }

    // MARK: - History

    private func addToHistory(_ text: String) {
        history.insert(text, at: 0)
        if history.count > historyLimit { history.removeLast() }

        historyMenu.removeAllItems()
        for (i, t) in history.enumerated() {
            let preview = "\(i + 1).  " + (t.count <= 52 ? t : String(t.prefix(49)) + "…")
            let item = NSMenuItem(title: preview, action: #selector(copyHistoryItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = t
            historyMenu.addItem(item)
        }
    }

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        OutputManager.copyToClipboard(text)
        showNotification("Copied to clipboard.")
    }

    // MARK: - Actions

    @objc private func openHelp() {
        // Look for docs.html in the app bundle Resources, then in the source directory
        let bundle = Bundle.main
        if let docsPath = bundle.path(forResource: "docs", ofType: "html") {
            NSWorkspace.shared.open(URL(fileURLWithPath: docsPath))
        } else {
            // Fallback: look relative to executable
            let execDir = (CommandLine.arguments.first.flatMap {
                URL(fileURLWithPath: $0).deletingLastPathComponent().path
            }) ?? "."
            let docsPath = (execDir as NSString).appendingPathComponent("docs.html")
            if FileManager.default.fileExists(atPath: docsPath) {
                NSWorkspace.shared.open(URL(fileURLWithPath: docsPath))
            } else {
                Log.warning("docs.html not found")
            }
        }
    }

    @objc private func openLog() {
        let logPath = NSHomeDirectory() + "/Library/Logs/TranscriptWhatYouHear.log"
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }

    @objc private func quitApp() {
        Log.info("Quitting")
        hotkeyManager.unregister()
        NSApp.terminate(nil)
    }

    // MARK: - Notifications

    private func showNotification(_ text: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "TranscriptWhatYouHear"
        content.body = text
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}
