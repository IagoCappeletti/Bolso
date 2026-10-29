import AppKit

/// Every alert Bolso shows, built in one place so screen renders match what people see.
enum Alerts {
    static func error(_ message: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Bolso"
        alert.informativeText = message
        return alert
    }
    static func accessibility() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "O Bolso precisa de permissão para colar"
        alert.informativeText = "O item já foi copiado: cole com ⌘V. Para o Bolso colar sozinho, ligue-o em Ajustes do Sistema → Privacidade e Segurança → Acessibilidade."
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Agora não")
        return alert
    }
    static func capturePermission() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "O Bolso precisa de permissão para capturar a tela"
        alert.informativeText = ScreenCaptureFailure.permission.localizedDescription
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Agora não")
        return alert
    }
    static func discardEdits() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Descartar as marcações?"
        alert.informativeText = "O que você marcou e ainda não copiou nem salvou será perdido."
        alert.addButton(withTitle: "Continuar editando")
        alert.addButton(withTitle: "Descartar").hasDestructiveAction = true
        return alert
    }
    static func restart(version: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Atualização do Bolso pronta"
        alert.informativeText = "A versão \(version) já foi baixada. Reiniciar agora limpa o histórico de cópias; com Depois, ela entra quando o Bolso fechar."
        alert.addButton(withTitle: "Reiniciar agora")
        alert.addButton(withTitle: "Depois")
        return alert
    }
}
