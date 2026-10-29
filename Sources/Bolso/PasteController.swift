import AppKit
import ApplicationServices
import Carbon

final class PasteController {
    private var generation = 0
    var report: ((String) -> Void)?
    func cancel() { generation += 1 }
    func paste(to target: NSRunningApplication?) {
        generation += 1
        let token = generation
        guard AXIsProcessTrusted() else {
            let alert = Alerts.accessibility()
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            return
        }
        guard let target, !target.isTerminated, target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            report?("O app anterior não está disponível. O item está na área de transferência; cole com ⌘V.")
            return
        }
        guard target.activate(options: [.activateIgnoringOtherApps]) else {
            report?("Não foi possível ativar o app anterior. Cole o item manualmente com ⌘V.")
            return
        }
        // Wait for activation and release of the hotkey/Option/Enter before posting.
        attempt(target: target, token: token, remaining: 40)
    }
    private func attempt(target: NSRunningApplication, token: Int, remaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, token == self.generation else { return }
            guard !target.isTerminated else { return }
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
            let keys = [kVK_Return, kVK_ANSI_V, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_KeypadEnter]
            let held = keys.contains { CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0)) }
            if !target.isActive || !flags.intersection(modifiers).isEmpty || held {
                if remaining > 0 { self.attempt(target: target, token: token, remaining: remaining - 1) }
                else { self.report?("A colagem automática foi cancelada: foco ou teclas ainda ocupados. O item está disponível para ⌘V.") }
                return
            }
            guard AXIsProcessTrusted(), let source = CGEventSource(stateID: .privateState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
