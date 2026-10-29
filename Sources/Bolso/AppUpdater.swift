import AppKit
import Sparkle

/// Sparkle downloads new GitHub releases in the background; restarting into them clears the
/// in-memory history, so the user chooses between now and the next quit, which installs anyway.
final class AppUpdater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private(set) var pendingVersion: String?
    /// A modal question must never sit under the frozen capture screen or interrupt the editor or panel.
    var isBusy: () -> Bool = { false }
    var onChange: (() -> Void)?
    /// Returns true to restart now.
    var ask: (String) -> Bool = AppUpdater.askToRestart
    private var install: (() -> Void)?
    private var asked = false
    private var retry: Timer?
    private var wake: NSObjectProtocol?
    private var lastCheck = Date.distantPast
    private var controller: SPUStandardUpdaterController?

    func start() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        // Sparkle's own schedule checks hourly; launch, wake, the history and captures check sooner.
        wake = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.checkNow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkNow() }
    }
    func checkNow() {
        lastCheck = Date()
        // Sparkle ignores checks while a session runs, such as a download already under way.
        guard let updater = controller?.updater, !updater.sessionInProgress else { return }
        updater.checkForUpdatesInBackground()
    }
    /// Opening the history or capturing also looks for a release, at most once every five minutes.
    @discardableResult
    func checkIfStale(now: Date = Date()) -> Bool {
        guard now.timeIntervalSince(lastCheck) >= 5 * 60 else { return false }
        checkNow()
        return true
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        offer(version: item.displayVersionString, install: immediateInstallationBlock)
        return true
    }

    func offer(version: String, install: @escaping () -> Void) {
        self.install = install
        // Later checks find the same download again; Depois must not become a question every few minutes.
        guard version != pendingVersion else { return }
        pendingVersion = version
        asked = false
        onChange?()
        askIfIdle()
    }

    func askIfIdle() {
        guard let version = pendingVersion, !asked else { return }
        whenIdle { [weak self] in
            guard let self, !self.asked else { return }
            self.asked = true
            if self.ask(version) { self.installNow() }
        }
    }

    func installNow() { install?() }

    // Sparkle shows its own alert only for updates it cannot install silently, such as an app the user may not
    // modify. A menu bar app would get that alert behind other windows, so Bolso brings it up in focus instead.
    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus && !isBusy()
    }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        whenIdle { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.controller?.checkForUpdates(nil)
        }
    }

    private func whenIdle(_ action: @escaping () -> Void) {
        retry?.invalidate(); retry = nil
        guard !isBusy() else {
            retry = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in self?.whenIdle(action) }
            return
        }
        action()
    }

    private static func askToRestart(_ version: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        return Alerts.restart(version: version).runModal() == .alertFirstButtonReturn
    }
}
