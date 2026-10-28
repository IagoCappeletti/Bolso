import AppKit
import BolsoCore
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = ClipboardStore()
    private var status: NSStatusItem!
    private var pauseItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var hotKey: HotKey?
    private var captureHotKey: HotKey?
    private var session: PanelSession?
    private var editor: ImageEditorSession?
    private var capture: ScreenCaptureSession?
    private let pasteController = PasteController()
    private var previousApp: NSRunningApplication?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = MenuBarIcon.make()
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Abrir Bolso", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(withTitle: "Capturar área da tela", action: #selector(startCapture), keyEquivalent: "")
        pauseItem = menu.addItem(withTitle: "Pausar captura", action: #selector(pause), keyEquivalent: "")
        menu.addItem(withTitle: "Limpar histórico", action: #selector(clear), keyEquivalent: "")
        loginItem = menu.addItem(withTitle: "Abrir ao iniciar o Mac", action: #selector(toggleLogin), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sair", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        status.menu = menu
        pasteController.report = { [weak self] in self?.showError($0) }
        do { hotKey = try HotKey { [weak self] in self?.togglePanel() } }
        catch { showError("Não foi possível registrar ⌘⇧V. Verifique se outro app usa o atalho.\n\(error)") }
        do { captureHotKey = try HotKey(keyCode: UInt32(kVK_ANSI_2), identifier: 2) { [weak self] in self?.startCapture() } }
        catch { showError("Não foi possível registrar ⌘⇧2 para capturar a tela. Verifique se outro app usa o atalho.\n\(error)") }
        DragFiles.clearAll()
        TextRecognizer.warmUp()
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
    }
    func menuWillOpen(_ menu: NSMenu) {
        pauseItem.title = store.paused ? "Retomar captura" : "Pausar captura"
        switch SMAppService.mainApp.status {
        case .enabled: loginItem.state = .on
        case .requiresApproval: loginItem.state = .mixed
        default: loginItem.state = .off
        }
    }
    @objc private func toggleLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled: try SMAppService.mainApp.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default:
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            showError("Não foi possível alterar a abertura no login. Execute o Bolso.app assinado, instalado em /Applications, e confira Ajustes do Sistema → Geral → Itens de Início.\n\(error.localizedDescription)")
        }
    }
    func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Bolso"
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    @objc private func togglePanel() {
        if let capture { capture.show(); return }
        if let editor { editor.show(); return }
        if let session { session.close(); return }
        pasteController.cancel()
        previousApp = NSWorkspace.shared.frontmostApplication
        let session = PanelSession(store: store)
        session.onClose = { [weak self, weak session] in
            guard let self else { return }
            self.session = nil
            // Editing and capturing keep Bolso in front; only dismissing or pasting hands focus back.
            if session?.closeReason != .edit, session?.closeReason != .capture,
               NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                self.previousApp?.activate(options: [.activateIgnoringOtherApps])
            }
        }
        session.onChoose = { [weak self] clip, plain in
            guard let self else { return }
            guard self.store.write(clip, plain: plain) else {
                self.session?.close()
                self.showError(clip.canPastePlain ? "Não foi possível copiar o item. Confira se os arquivos ainda existem." : "Esta imagem não possui texto. Use Enter sem Option para colar a imagem.")
                return
            }
            let target = self.previousApp
            self.session?.close(reason: .paste)
            self.pasteController.paste(to: target)
        }
        session.onEdit = { [weak self] clip in
            guard let self, let image = clip.editableImage else { return }
            let editor = ImageEditorSession(image: image, store: self.store)
            self.editor = editor
            editor.onClose = { [weak self] in
                guard let self else { return }
                self.editor = nil
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                    self.previousApp?.activate(options: [.activateIgnoringOtherApps])
                }
            }
            self.session?.close(reason: .edit)
            editor.show()
        }
        self.session = session
        session.show()
    }
    @objc private func startCapture() {
        if let capture { capture.show(); return }
        let previous = session == nil ? NSWorkspace.shared.frontmostApplication : previousApp
        let permission = ScreenCaptureSession.ensurePermission()
        guard permission.granted else {
            session?.close()
            if !permission.prompted { showCapturePermission() }
            return
        }
        let capture = ScreenCaptureSession(store: store)
        capture.onClose = { [weak self] in
            self?.capture = nil
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                previous?.activate(options: [.activateIgnoringOtherApps])
            }
        }
        // An open history panel belongs in the shot, so it closes only once the screens are frozen.
        capture.onCaptured = { [weak self] in self?.session?.close(reason: .capture) }
        capture.onError = { [weak self] in self?.session?.close(); self?.showError($0) }
        self.capture = capture
        capture.start()
    }
    private func showCapturePermission() {
        let alert = NSAlert()
        alert.messageText = "Bolso precisa de permissão para capturar a tela"
        alert.informativeText = ScreenCaptureFailure.permission.localizedDescription
        alert.addButton(withTitle: "Abrir Ajustes do Sistema")
        alert.addButton(withTitle: "Agora não")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func pause() { store.togglePause() }
    @objc private func clear() { store.clear() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        capture?.canClose() == false || editor?.canClose() == false ? .terminateCancel : .terminateNow
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
if CommandLine.arguments.contains("--editor-demo") {
    runEditorDemo()
} else if CommandLine.arguments.contains("--capture-self-test") {
    runCaptureChecks()
} else if CommandLine.arguments.contains("--editor-self-test") {
    runEditorChecks()
} else if CommandLine.arguments.contains("--ui-self-test") {
    runPanelChecks()
} else if CommandLine.arguments.contains("--self-test") {
    runSelfChecks()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
