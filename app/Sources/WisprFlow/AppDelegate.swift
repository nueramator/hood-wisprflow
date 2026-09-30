import AppKit
import ApplicationServices

/// Wires the pipeline together and owns the menu-bar UI:
/// hold hotkey -> record -> (release) -> transcribe -> clean up -> inject.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings = Settings.load()
    private let recorder = AudioRecorder()
    private var whisper: WhisperEngine!
    private let hotkey = HotkeyMonitor()

    private var statusItem: NSStatusItem!
    private var statusMenuTitleItem: NSMenuItem!
    private var aiToggleItem: NSMenuItem!

    private let workQueue = DispatchQueue(label: "wisprflow.pipeline")
    private var engineReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        whisper = WhisperEngine(settings: settings)

        ensureAccessibilityPermission()

        recorder.requestPermission { granted in
            DispatchQueue.main.async {
                if !granted { self.setStatus("⚠︎ Microphone denied — enable in System Settings") }
            }
        }

        // Start the resident whisper server off the main thread.
        setStatus("Starting speech engine…")
        workQueue.async {
            do {
                try self.whisper.start()
                self.engineReady = true
                DispatchQueue.main.async { self.setIdle() }
            } catch {
                DispatchQueue.main.async { self.setStatus("⚠︎ \(error)") }
            }
        }

        hotkey.onPress = { [weak self] in self?.beginRecording() }
        hotkey.onRelease = { [weak self] in self?.endRecording() }
        if !hotkey.start() {
            setStatus("⚠︎ Hotkey needs Accessibility permission")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        whisper?.stop()
    }

    // MARK: - Recording pipeline

    private func beginRecording() {
        guard engineReady, !recorder.isRecording else { return }
        do {
            try recorder.start()
            setMenuBarSymbol(recording: true)
            setStatus("Listening… (release ⌥Space to insert)")
        } catch {
            setStatus("⚠︎ Mic error: \(error.localizedDescription)")
        }
    }

    private func endRecording() {
        guard recorder.isRecording else { return }
        let samples = recorder.stop()
        setMenuBarSymbol(recording: false)

        guard samples.count > 1600 else {   // < ~0.1s → ignore
            setIdle()
            return
        }
        setStatus("Transcribing…")

        workQueue.async {
            do {
                let wavURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("wispr-\(UUID().uuidString).wav")
                try WavWriter.write(samples: samples, to: wavURL)
                defer { try? FileManager.default.removeItem(at: wavURL) }

                let raw = try self.whisper.transcribe(wavURL: wavURL)
                guard !raw.isEmpty else {
                    DispatchQueue.main.async { self.setIdle() }
                    return
                }

                let appName = DispatchQueue.main.sync { AppContext.frontmostAppName() }

                var finalText = Cleanup.local(raw, dictionary: self.settings.dictionary)
                if self.settings.aiCleanupEnabled {
                    DispatchQueue.main.async { self.setStatus("Polishing…") }
                    if let polished = Cleanup.ai(finalText, appName: appName,
                                                 model: self.settings.cleanupModel) {
                        finalText = polished
                    }
                }

                let toInsert = finalText
                DispatchQueue.main.async {
                    TextInjector.insert(toInsert)
                    self.setIdle()
                }
            } catch {
                DispatchQueue.main.async { self.setStatus("⚠︎ \(error)") }
            }
        }
    }

    // MARK: - Permissions

    private func ensureAccessibilityPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            setStatus("⚠︎ Grant Accessibility, then relaunch")
        }
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setMenuBarSymbol(recording: false)

        let menu = NSMenu()
        statusMenuTitleItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusMenuTitleItem.isEnabled = false
        menu.addItem(statusMenuTitleItem)
        menu.addItem(.separator())

        let hint = NSMenuItem(title: "Hold  ⌥Space  to dictate", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        aiToggleItem = NSMenuItem(title: "AI Cleanup (Claude)",
                                  action: #selector(toggleAICleanup), keyEquivalent: "")
        aiToggleItem.target = self
        aiToggleItem.state = settings.aiCleanupEnabled ? .on : .off
        menu.addItem(aiToggleItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Wispr Flow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func setMenuBarSymbol(recording: Bool) {
        guard let button = statusItem.button else { return }
        let name = recording ? "mic.fill" : "mic"
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Wispr Flow") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = recording ? "●" : "🎙"
        }
    }

    private func setStatus(_ text: String) {
        statusMenuTitleItem.title = text
    }

    private func setIdle() {
        setStatus(engineReady ? "Ready" : "Starting…")
    }

    @objc private func toggleAICleanup() {
        settings.aiCleanupEnabled.toggle()
        aiToggleItem.state = settings.aiCleanupEnabled ? .on : .off
        settings.save()
        if settings.aiCleanupEnabled &&
            (ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? "").isEmpty {
            setStatus("⚠︎ Set ANTHROPIC_API_KEY for AI cleanup")
        }
    }
}
