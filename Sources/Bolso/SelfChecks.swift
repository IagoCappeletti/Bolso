import AppKit

func runSelfChecks() {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    var store: ClipboardStore? = ClipboardStore(board: board)
    weak var weakStore: ClipboardStore?
    weakStore = store
    func tick() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.8)) }
    board.clearContents()
    board.setString("primeiro", forType: .string)
    tick()
    precondition(store!.items.count == 1)
    tick()
    precondition(store!.items.count == 1)
    store!.togglePause()
    board.clearContents()
    board.setString("ignorado", forType: .string)
    tick()
    precondition(store!.items.count == 1)
    store!.togglePause()
    tick()
    precondition(store!.items.count == 1)
    board.clearContents()
    board.setString("segundo", forType: .string)
    tick()
    precondition(store!.items.count == 2 && store!.items.first!.text == "segundo")
    precondition(store!.write(store!.items[1], plain: true))
    tick()
    precondition(store!.items.count == 2 && store!.items.first!.text == "primeiro")
    store!.clear()
    tick()
    precondition(store!.items.isEmpty)
    weak var weakSession: PanelSession?
    autoreleasepool {
        let session = PanelSession(store: store!)
        weakSession = session
        session.query = "segundo"
    }
    precondition(weakSession == nil)
    store = nil
    precondition(weakStore == nil)
    print("PASS: timer, pausa/retomada, escrita própria, limpeza e liberação de store/sessão")
}

func runPanelChecks() {
    let previous = NSWorkspace.shared.frontmostApplication
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    defer { previous?.activate(options: [.activateIgnoringOtherApps]) }
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let store = ClipboardStore(board: board)
    board.clearContents()
    board.setString("Teste do painel", forType: .string)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.8))
    precondition(store.items.count == 1)
    for _ in 0..<5 {
        weak var weakPanel: NSPanel?
        weak var weakSession: PanelSession?
        autoreleasepool {
            let session = PanelSession(store: store)
            weakSession = session
            session.show()
            weakPanel = session.panel
            precondition(weakPanel != nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
            if let path = ProcessInfo.processInfo.environment["BOLSO_PREVIEW_PATH"],
               let view = session.panel?.contentView,
               let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    try! png.write(to: URL(fileURLWithPath: path))
                }
            }
            var chosen = false
            session.onChoose = { clip, plain in chosen = clip.text == "Teste do painel" && plain }
            let number = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.option], timestamp: 0, windowNumber: session.panel!.windowNumber, context: nil, characters: "¡", charactersIgnoringModifiers: "¡", isARepeat: false, keyCode: 18)!
            precondition(session.handle(number) && chosen)
            session.query = "não existe"
            chosen = false
            precondition(session.handle(number) && !chosen)
            session.close()
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        precondition(weakPanel == nil, "Panel retained after closing")
        precondition(weakSession == nil, "Session retained after closing")
    }
    print("PASS: 5 painéis reais criados/liberados; Option+1 e lista filtrada")
}
