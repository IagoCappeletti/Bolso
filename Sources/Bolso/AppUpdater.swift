import AppKit
import Sparkle

/// Sparkle downloads new GitHub releases in the background; restarting into them clears the
/// in-memory history, so the user chooses between now and the next quit, which installs anyway.
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    private(set) var pendingVersion: String?
    /// A modal question must never sit under the frozen capture screen or interrupt the editor or panel.
    var isBusy: () -> Bool = { false }
    var onChange: (() -> Void)?
    /// Returns true to restart now.
    var ask: (String) -> Bool = AppUpdater.askToRestart
    private var install: (() -> Void)?
    private var asked = false
    private var retry: Timer?
    private var controller: SPUStandardUpdaterController?

    func start() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }
    func checkNow() { controller?.updater.checkForUpdatesInBackground() }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        offer(version: item.displayVersionString, install: immediateInstallationBlock)
        return true
    }

    func offer(version: String, install: @escaping () -> Void) {
        pendingVersion = version
        self.install = install
        asked = false
        onChange?()
        askIfIdle()
    }

    func askIfIdle() {
        retry?.invalidate(); retry = nil
        guard let version = pendingVersion, !asked else { return }
        guard !isBusy() else {
            retry = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in self?.askIfIdle() }
            return
        }
        asked = true
        if ask(version) { installNow() }
    }

    func installNow() { install?() }

    private static func askToRestart(_ version: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Bolso \(version) pronto para instalar"
        alert.informativeText = "Reiniciar agora limpa o histórico de cópias. Se preferir, a atualização entra quando o Bolso fechar."
        alert.addButton(withTitle: "Reiniciar agora")
        alert.addButton(withTitle: "Depois")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
