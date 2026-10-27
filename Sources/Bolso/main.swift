import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = ClipboardStore()
    private var status: NSStatusItem!
    private var pauseItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var hotKey: HotKey?
    private var session: PanelSession?
    private let pasteController = PasteController()
    private var previousApp: NSRunningApplication?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = MenuBarIcon.make()
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Abrir Bolso", action: #selector(togglePanel), keyEquivalent: "")
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
        if let session { session.close(); return }
        pasteController.cancel()
        previousApp = NSWorkspace.shared.frontmostApplication
        let session = PanelSession(store: store)
        session.onClose = { [weak self] in
            guard let self else { return }
            self.session = nil
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                self.previousApp?.activate(options: [.activateIgnoringOtherApps])
            }
        }
        session.onChoose = { [weak self] clip, plain in
            guard let self else { return }
            guard self.store.write(clip, plain: plain) else {
                self.session?.close()
                self.showError(clip.canPastePlain ? "Não foi possível copiar o item. Confira se os arquivos ainda existem." : "Esta imagem não possui texto. Use Enter sem Option para colar a miniatura.")
                return
            }
            let target = self.previousApp
            self.session?.close()
            self.pasteController.paste(to: target)
        }
        self.session = session
        session.show()
    }
    @objc private func pause() { store.togglePause() }
    @objc private func clear() { store.clear() }
    @objc private func quit() { NSApp.terminate(nil) }
}
if CommandLine.arguments.contains("--ui-self-test") {
    runPanelChecks()
} else if CommandLine.arguments.contains("--self-test") {
    runSelfChecks()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
