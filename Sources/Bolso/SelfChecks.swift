import AppKit
import BolsoCore

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
    }
    precondition(weakSession == nil)
    store = nil
    precondition(weakStore == nil)
    print("PASS: timer, pausa/retomada, escrita própria, limpeza e liberação de store/sessão")
    updaterChecks()
}

/// Run from a bundle whose feed lists a newer build: Sparkle must download and verify it, and the bundle is replaced on quit.
func runUpdateCheck() {
    setbuf(stdout, nil)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let updater = AppUpdater()
    updater.ask = { version in
        print("PASS: \(version) baixada e com assinatura verificada; o Bolso fecha para instalar")
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return false
    }
    updater.start()
    updater.checkNow()
    DispatchQueue.main.asyncAfter(deadline: .now() + 90) { print("FAIL: nenhuma atualização em 90 s"); exit(1) }
    app.run()
}

private func updaterChecks() {
    let updater = AppUpdater()
    var busy = true, answer = false, installs = 0, changes = 0
    var questions: [String] = []
    updater.isBusy = { busy }
    updater.ask = { questions.append($0); return answer }
    updater.onChange = { changes += 1 }
    updater.offer(version: "9.9.9") { installs += 1 }
    precondition(questions.isEmpty && updater.pendingVersion == "9.9.9" && changes == 1, "A capture, the editor or the panel holds the question back")
    busy = false
    updater.askIfIdle()
    precondition(questions == ["9.9.9"] && installs == 0, "Idle, it asks once; Depois leaves the update for the next quit")
    updater.askIfIdle()
    precondition(questions.count == 1, "Depois is not asked again")
    updater.installNow()
    precondition(installs == 1, "The menu item installs the waiting update")
    answer = true
    updater.offer(version: "9.9.10") { installs += 1 }
    precondition(questions.last == "9.9.10" && installs == 2, "Reiniciar agora installs right away")
    print("PASS: atualização espera captura/editor/painel, pergunta uma vez, Depois instala ao sair e o menu instala na hora")
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
            let digit = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: session.panel!.windowNumber, context: nil, characters: "1", charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 18)!
            precondition(!session.handle(digit) && !chosen, "Only ⌘ with a digit pastes")
            let number = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0, windowNumber: session.panel!.windowNumber, context: nil, characters: "¡", charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 18)!
            precondition(session.handle(number) && chosen, "⌘⌥1 pastes the first item as plain text")
            session.close()
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        precondition(weakPanel == nil, "Panel retained after closing")
        precondition(weakSession == nil, "Session retained after closing")
    }
    let picture = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    board.clearContents(); board.setData(picture.representation(using: .png, properties: [:])!, forType: .png)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.8))
    let image = store.items[0]
    precondition(image.editableImage != nil)
    autoreleasepool {
        let session = PanelSession(store: store)
        session.show()
        let canceled = session.dragFiles(for: image)
        precondition(canceled.count == 1 && canceled[0].pathExtension == "png" && NSBitmapImageRep(data: try! Data(contentsOf: canceled[0]))?.pixelsWide == 40, "History images drag out as full PNGs")
        session.endDrag(canceled, delivered: false)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        precondition(!FileManager.default.fileExists(atPath: canceled[0].path) && session.panel != nil, "A canceled drag removes the temporary image and keeps the panel")
        let delivered = session.dragFiles(for: image)
        session.endDrag(delivered, delivered: true)
        precondition(session.panel == nil && FileManager.default.fileExists(atPath: delivered[0].path), "A delivered drag closes the panel and leaves the file for the receiver")
        // The real app shares this temporary folder, so remove only this check's file.
        try? FileManager.default.removeItem(at: delivered[0].deletingLastPathComponent())
        let document = FileManager.default.temporaryDirectory.appendingPathComponent("Bolso-painel-\(UUID().uuidString).txt")
        try! Data("arquivo".utf8).write(to: document)
        defer { try? FileManager.default.removeItem(at: document) }
        board.clearContents(); board.writeObjects([document as NSURL])
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.8))
        let files = session.dragFiles(for: store.items[0])
        precondition(files.map(\.standardizedFileURL) == [document.standardizedFileURL], "Copied files drag out as themselves")
        session.endDrag(files, delivered: false)
        precondition(FileManager.default.fileExists(atPath: document.path), "Dragging a copied file never deletes it")
        precondition(session.dragFiles(for: store.items.first { $0.text == "Teste do painel" }!).isEmpty, "Text items are not dragged")
    }
    var clicked = false, prepared = false
    let source = DragSourceView(prepare: { prepared = true; return [] }, finish: { _, _ in })
    source.click = { clicked = true }
    let holder = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
    holder.isReleasedWhenClosed = false
    source.frame = holder.contentView!.bounds; holder.contentView!.addSubview(source)
    func press(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: holder.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    source.mouseDown(with: press(.leftMouseDown, NSPoint(x: 40, y: 40)))
    source.mouseDragged(with: press(.leftMouseDragged, NSPoint(x: 41, y: 41)))
    source.mouseUp(with: press(.leftMouseUp, NSPoint(x: 41, y: 41)))
    precondition(clicked && !prepared, "A click with a tiny wobble stays a click")
    holder.close()
    print("PASS: 5 painéis reais criados/liberados; ⌘⌥1, dígito sozinho não cola e arrastar imagens/arquivos do histórico")
}

func runEditorChecks() {
    let previous = NSWorkspace.shared.frontmostApplication
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory); app.finishLaunching()
    defer { previous?.activate(options: [.activateIgnoringOtherApps]) }
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let store = ClipboardStore(board: board)
    store.togglePause()
    isolatePreferences()
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 800, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    memset(bitmap.bitmapData!, 240, bitmap.bytesPerRow * bitmap.pixelsHigh)
    let png = bitmap.representation(using: .png, properties: [:])!
    let clip = Clip.renderedImage(png)!
    precondition(store.write(clip, plain: false))
    func awaitReady(_ session: ImageEditorSession) {
        let timeout = Date(timeIntervalSinceNow: 10)
        while session.busy && Date() < timeout { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
        precondition(!session.busy && session.document != nil)
    }
    for index in 0..<5 {
        weak var weakSession: ImageEditorSession?
        weak var weakWindow: NSWindow?
        autoreleasepool {
            let session = ImageEditorSession(image: clip.editableImage!, store: store)
            weakSession = session; weakWindow = session.window
            session.show(); awaitReady(session)
            if index == 0 {
                func canvas(in view: NSView) -> AnnotationCanvasView? {
                    if let canvas = view as? AnnotationCanvasView { return canvas }
                    return view.subviews.lazy.compactMap { canvas(in: $0) }.first
                }
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
                let drawing = canvas(in: session.window!.contentView!)!
                func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
                    NSEvent.mouseEvent(with: type, location: drawing.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                                       windowNumber: session.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                }
                let start = NSPoint(x: drawing.bounds.midX, y: drawing.bounds.midY)
                let end = NSPoint(x: start.x + 40, y: start.y + 30)
                session.tool = .rectangle
                drawing.mouseDown(with: mouse(.leftMouseDown, start))
                drawing.mouseDragged(with: mouse(.leftMouseDragged, end))
                drawing.mouseUp(with: mouse(.leftMouseUp, end))
                precondition(session.document!.annotations.count == 1)
                let anchor = session.document!.annotations[0].points[0]
                precondition(abs(anchor.x - 600) < 1 && abs(anchor.y - 400) < 1, "Pointer must map to image pixels")
                session.document!.undo()
                drawing.mouseDown(with: mouse(.leftMouseDown, start))
                precondition(drawing.cancelGesture())
                drawing.mouseUp(with: mouse(.leftMouseUp, end))
                precondition(session.document!.annotations.isEmpty, "Canceled gesture must not commit")
            }
            session.document!.add(Annotation(tool: .rectangle, points: [CGPoint(x: 120, y: 180), CGPoint(x: 640, y: 440)], color: .systemPurple, width: 8))
            session.document!.add(Annotation(tool: .arrow, points: [CGPoint(x: 900, y: 600), CGPoint(x: 640, y: 440)], color: .systemRed, width: 8))
            session.document!.add(Annotation(tool: .text, points: [CGPoint(x: 140, y: 230)], color: .black, width: 5, text: "Uma ideia merece destaque.", fontSize: 28))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            if index == 0, let path = ProcessInfo.processInfo.environment["BOLSO_EDITOR_PREVIEW_PATH"],
               let view = session.window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
            }
            session.copyImage(); awaitReady(session)
            precondition(!session.document!.isDirty)
            precondition(store.items.count == 2, "Explicit copy while paused must preserve original and deduplicate output")
            store.clear()
            precondition(session.document != nil, "Clear history must not discard editor")
            precondition(store.write(clip, plain: false))
            session.window?.performClose(nil)
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        precondition(weakSession == nil, "Editor session leaked")
        precondition(weakWindow == nil, "Editor window leaked")
    }
    let panel = PanelSession(store: store)
    var edited = false, pasted = false
    panel.onEdit = { _ in edited = true }
    panel.onChoose = { _, _ in pasted = true }
    panel.edit(0)
    precondition(edited && !pasted)
    print("PASS: 5 editor windows released, copy while paused, clear while editing and separate edit action")
}

// Preview mode uses an isolated clipboard and never reads or changes the user's clipboard.
func runEditorDemo() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory); app.finishLaunching()
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let store = ClipboardStore(board: board)
    store.togglePause()
    isolatePreferences()
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 800, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    memset(bitmap.bitmapData!, 255, bitmap.bytesPerRow * bitmap.pixelsHigh)
    let image = ImagePayload(data: bitmap.representation(using: .png, properties: [:])!)!
    let session = ImageEditorSession(image: image, store: store)
    session.show()
    session.onClose = { app.stop(nil) }
    app.run()
}

// Synthetic 2× snapshots keep this check independent of the Screen Recording permission.
func runCaptureChecks() {
    let previous = NSWorkspace.shared.frontmostApplication
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory); app.finishLaunching()
    defer { previous?.activate(options: [.activateIgnoringOtherApps]) }
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let store = ClipboardStore(board: board)
    store.togglePause()
    isolatePreferences()
    // As at app launch, so the OCR model is being prepared while the other checks run.
    TextRecognizer.warmUp()
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    memset(bitmap.bitmapData!, 255, bitmap.bytesPerRow * bitmap.pixelsHigh)
    let marker = bitmap.bitmapData!.advanced(by: 110 * bitmap.bytesPerRow + 210 * 4)
    marker[0] = 0; marker[1] = 0; marker[2] = 255; marker[3] = 255
    let screen = NSScreen.main!.visibleFrame
    let first = CaptureDisplay(id: 0, frame: CGRect(x: screen.minX + 40, y: screen.minY + 40, width: 400, height: 300), visibleFrame: screen, pixelWidth: 800, pixelHeight: 600)
    let second = CaptureDisplay(id: 1, frame: first.frame.offsetBy(dx: 420, dy: 0), visibleFrame: screen, pixelWidth: 800, pixelHeight: 600)
    func mouse(_ type: NSEvent.EventType, _ point: NSPoint, in view: NSView) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                           windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    func drag(_ view: NSView, from start: NSPoint, to end: NSPoint) {
        view.mouseDown(with: mouse(.leftMouseDown, start, in: view))
        view.mouseDragged(with: mouse(.leftMouseDragged, end, in: view))
        view.mouseUp(with: mouse(.leftMouseUp, end, in: view))
    }
    weak var weakSession: ScreenCaptureSession?
    weak var weakOverlay: NSWindow?
    autoreleasepool {
        let session = ScreenCaptureSession(store: store)
        weakSession = session
        var closed = false
        session.onClose = { closed = true }
        let panel = PanelSession(store: store)
        panel.show()
        var panelOpenWhileFrozen = false
        session.onCaptured = { panelOpenWhileFrozen = panel.panel != nil && session.overlays.isEmpty; panel.close(reason: .capture) }
        session.present([CapturedDisplay(display: first, image: bitmap.cgImage!)])
        precondition(panelOpenWhileFrozen && panel.panel == nil && panel.closeReason == .capture, "History panel must stay open until the screens are frozen")
        weakOverlay = session.overlays.first
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: session.overlays[0].windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        app.sendEvent(escape)
        precondition(closed && session.overlays.isEmpty, "Escape must cancel the selection")
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    precondition(weakSession == nil && weakOverlay == nil, "Canceled capture leaked")
    for index in 0..<3 {
        weak var weakSession: ScreenCaptureSession?
        weak var weakEditor: ImageEditorSession?
        weak var weakToolbar: NSWindow?
        var overlays: [() -> NSWindow?] = []
        autoreleasepool {
            let session = ScreenCaptureSession(store: store)
            weakSession = session
            var closed = false
            session.onClose = { closed = true }
            session.present([CapturedDisplay(display: first, image: bitmap.cgImage!), CapturedDisplay(display: second, image: bitmap.cgImage!)])
            precondition(session.overlays.count == 2)
            for window in session.overlays { overlays.append { [weak window] in window } }
            let selection = session.overlays[0].contentView as! CaptureSelectionView
            drag(selection, from: NSPoint(x: 150.25, y: 80), to: NSPoint(x: 100, y: 50))
            precondition(session.overlays.count == 1, "Other displays must be released once a region is chosen")
            let editor = session.editor!, document = editor.document!
            weakEditor = editor; weakToolbar = editor.window
            precondition(document.image.width == 101 && document.image.height == 60, "2× selection must crop whole pixels")
            precondition(selection.canvas!.frame == CGRect(x: 100, y: 50, width: 50.5, height: 30), "Canvas must sit on the cropped pixels")
            let toolbar = editor.window!
            precondition(toolbar.level.rawValue > session.overlays[0].level.rawValue && toolbar.isVisible)
            precondition(screen.contains(toolbar.frame), "Toolbar must stay inside the visible frame")
            let crop = NSBitmapImageRep(data: ImageAnnotationRenderer.png(image: document.image, annotations: [])!)!
            precondition(crop.colorAt(x: 10, y: 10)!.blueComponent > 0.9 && crop.colorAt(x: 10, y: 10)!.redComponent < 0.1, "Crop must keep the selected pixels")
            editor.tool = .rectangle
            drag(selection.canvas!, from: NSPoint(x: 10, y: 5), to: NSPoint(x: 40, y: 25))
            precondition(document.annotations.count == 1)
            let anchor = document.annotations[0].points[0]
            precondition(abs(anchor.x - 20) < 1 && abs(anchor.y - 10) < 1, "Canvas points must map to capture pixels")
            editor.tool = .text; editor.text = "Oi"
            drag(selection.canvas!, from: NSPoint(x: 10, y: 5), to: NSPoint(x: 30, y: 20))
            precondition(document.annotations.count == 2 && document.annotations[1].points.count == 1)
            let label = document.annotations[1].points[0]
            precondition(abs(label.x - 60) < 1 && abs(label.y - 40) < 1, "Text must land where the pointer is released")
            if index == 0, let path = ProcessInfo.processInfo.environment["BOLSO_CAPTURE_PREVIEW_PATH"],
               let view = toolbar.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
                view.cacheDisplay(in: view.bounds, to: rep)
                try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
            }
            editor.copyImage()
            let timeout = Date(timeIntervalSinceNow: 10)
            while !closed && Date() < timeout { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
            precondition(closed && session.overlays.isEmpty && session.editor == nil, "Copy must finish the capture")
            precondition(store.items.first?.editableImage?.width == 101, "Copied capture must keep full resolution")
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        precondition(weakSession == nil && weakEditor == nil && weakToolbar == nil, "Capture session leaked")
        precondition(overlays.allSatisfy { $0() == nil }, "Capture overlay leaked")
    }
    precondition(store.items.count == 1, "Identical captures must deduplicate in history")
    print("PASS: Esc cancela, várias telas, recorte 2×, mapeamento do canvas, cópia em resolução total e 3 capturas liberadas")
    captureToolChecks(store: store, display: first)
    guard CGPreflightScreenCaptureAccess() else { print("SKIP: captura real sem permissão de Gravação da Tela"); return }
    // A locked screen or a sleeping display offers no displays to ScreenCaptureKit.
    let locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
    guard !locked, CGDisplayIsAsleep(CGMainDisplayID()) == 0 else { print("SKIP: captura real com a tela bloqueada ou desligada"); return }
    var real: Result<[CapturedDisplay], Error>?
    let displays = CaptureDisplay.connected()
    Task { do { real = .success(try await ScreenCaptureProvider.capture(displays)) } catch { real = .failure(error) } }
    let timeout = Date(timeIntervalSinceNow: 10)
    while real == nil && Date() < timeout { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
    let snapshots = try! real!.get()
    precondition(snapshots.count == displays.count)
    for snapshot in snapshots {
        precondition(snapshot.image.width == snapshot.display.pixelWidth && snapshot.image.height == snapshot.display.pixelHeight, "Real capture must match the display's pixels")
    }
    print("PASS: captura real de \(snapshots.count) tela(s): " + snapshots.map { "\($0.image.width)×\($0.image.height)" }.joined(separator: ", "))
}

private func isolatePreferences() {
    let suite = "dev.personal.Bolso.checks"
    UserDefaults().removePersistentDomain(forName: suite)
    ImageEditorSession.preferences = UserDefaults(suiteName: suite)!
}

private func captureToolChecks(store: ClipboardStore, display: CaptureDisplay) {
    let white = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    memset(white.bitmapData!, 255, white.bytesPerRow * white.pixelsHigh)
    let words = Annotation(tool: .text, points: [CGPoint(x: 420, y: 400)], color: .black, width: 5, text: "Bolso 2026", fontSize: 56)
    let screen = ImageAnnotationRenderer.render(image: white.cgImage!, annotations: [words])!
    var snapshot = CapturedDisplay(display: display, image: screen)
    snapshot.windows = [CGRect(x: 40, y: 30, width: 120, height: 80)]
    func event(_ type: NSEvent.EventType, _ point: NSPoint, in view: NSView) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                           windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    func drag(_ view: NSView, from start: NSPoint, to end: NSPoint) {
        view.mouseDown(with: event(.leftMouseDown, start, in: view))
        if start != end { view.mouseDragged(with: event(.leftMouseDragged, end, in: view)) }
        view.mouseUp(with: event(.leftMouseUp, end, in: view))
    }
    func wait(seconds: TimeInterval = 15, until condition: () -> Bool) {
        let timeout = Date(timeIntervalSinceNow: seconds)
        while !condition() && Date() < timeout { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
    }
    weak var weakSession: ScreenCaptureSession?
    autoreleasepool {
        let session = ScreenCaptureSession(store: store)
        weakSession = session
        var closed = false
        session.onClose = { closed = true }
        session.present([snapshot])
        let view = session.overlays[0].contentView as! CaptureSelectionView
        view.mouseMoved(with: event(.mouseMoved, NSPoint(x: 60, y: 50), in: view))
        drag(view, from: NSPoint(x: 60, y: 50), to: NSPoint(x: 60, y: 50))
        let editor = session.editor!, document = editor.document!
        precondition(document.image.width == 240 && document.image.height == 160, "A click must capture the window under the pointer")
        let canvas = view.canvas!
        func hit(_ point: NSPoint) -> NSView? { view.hitTest(view.convert(point, to: view.superview)) }
        precondition(view.canAdjust && hit(NSPoint(x: 160, y: 70)) === view, "Edge handles must win over the canvas")
        precondition(hit(NSPoint(x: 100, y: 70)) === canvas, "The interior keeps drawing")
        drag(view, from: NSPoint(x: 160, y: 70), to: NSPoint(x: 200, y: 70))
        precondition(document.image.width == 320 && canvas.frame == CGRect(x: 40, y: 30, width: 160, height: 80) && !canvas.isHidden, "Dragging a handle must re-crop")
        drag(view, from: NSPoint(x: 250, y: 150), to: NSPoint(x: 350, y: 250))
        precondition(document.image.width == 200 && canvas.frame == CGRect(x: 250, y: 150, width: 100, height: 100), "Dragging outside must pick a new region")
        editor.tool = .rectangle; editor.color = .systemYellow; editor.width = 9
        drag(canvas, from: NSPoint(x: 10, y: 10), to: NSPoint(x: 40, y: 40))
        precondition(!view.canAdjust && hit(NSPoint(x: 348, y: 200)) === canvas, "Marks lock the region")
        drag(view, from: NSPoint(x: 20, y: 20), to: NSPoint(x: 120, y: 120))
        precondition(document.image.width == 200, "A locked region ignores new drags outside")
        let file = editor.beginDrag()!
        let overlay = session.overlays[0]
        precondition(FileManager.default.fileExists(atPath: file.path) && overlay.alphaValue == 0 && overlay.ignoresMouseEvents, "The frozen screen steps aside while dragging")
        precondition(NSBitmapImageRep(data: try! Data(contentsOf: file))!.pixelsWide == 200)
        editor.endDrag(file: file, delivered: false)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        precondition(overlay.alphaValue == 1 && !overlay.ignoresMouseEvents && !FileManager.default.fileExists(atPath: file.path), "A canceled drag restores the capture and removes the file")
        precondition(!closed && document.isDirty)
        let delivered = editor.beginDrag()!
        editor.endDrag(file: delivered, delivered: true)
        wait { closed }
        precondition(closed && session.editor == nil, "A completed drag finishes the capture")
        // The real app shares this temporary folder, so remove only this check's file.
        try? FileManager.default.removeItem(at: delivered.deletingLastPathComponent())
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    precondition(weakSession == nil, "Capture session leaked after drag")
    autoreleasepool {
        let session = ScreenCaptureSession(store: store)
        weakSession = session
        var closed = false
        session.onClose = { closed = true }
        session.present([snapshot])
        let view = session.overlays[0].contentView as! CaptureSelectionView
        drag(view, from: NSPoint(x: 250, y: 150), to: NSPoint(x: 350, y: 250))
        let editor = session.editor!, document = editor.document!, canvas = view.canvas!
        let grip = CaptureGeometry.moveGrip(for: canvas.frame, in: view.bounds)
        precondition(view.hitTest(view.convert(NSPoint(x: grip.midX, y: grip.midY), to: view.superview)) === view, "The move grip must win over the canvas")
        let before = document.image
        drag(view, from: NSPoint(x: grip.midX, y: grip.midY), to: NSPoint(x: grip.midX - 50, y: grip.midY + 30))
        precondition(canvas.frame == CGRect(x: 200, y: 180, width: 100, height: 100) && !canvas.isHidden, "The grip must move the region")
        precondition(document.image.width == 200 && document.image.height == 200 && document.image !== before, "Moving must re-crop at the same size")
        editor.tool = .rectangle
        drag(canvas, from: NSPoint(x: 10, y: 10), to: NSPoint(x: 40, y: 40))
        // runModal drops alerts below the frozen screen; a modal here would lock the Mac.
        var sawModal = false
        let watchdog = Timer(timeInterval: 0.3, repeats: false) { _ in sawModal = true; NSApp.abortModal() }
        RunLoop.main.add(watchdog, forMode: .modalPanel)
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: session.overlays[0].windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        NSApp.sendEvent(escape)
        watchdog.invalidate()
        precondition(!sawModal, "Canceling with marks must never open a modal over the frozen screen")
        precondition(!closed && editor.confirmingDiscard && session.overlays[0].isVisible, "Canceling with marks must ask in the toolbar")
        drag(canvas, from: NSPoint(x: 50, y: 50), to: NSPoint(x: 70, y: 70))
        precondition(!editor.confirmingDiscard, "A new mark withdraws the question")
        editor.window!.performClose(nil)
        precondition(!closed && editor.confirmingDiscard)
        editor.window!.performClose(nil)
        precondition(closed && session.editor == nil && session.overlays.isEmpty, "Asking twice discards the marks")
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    precondition(weakSession == nil, "Capture session leaked after discarding")
    autoreleasepool {
        let session = ScreenCaptureSession(store: store)
        weakSession = session
        var closed = false
        session.onClose = { closed = true }
        session.present([snapshot])
        drag(session.overlays[0].contentView!, from: NSPoint(x: 195, y: 180), to: NSPoint(x: 385, y: 225))
        let editor = session.editor!
        editor.copyText()
        precondition(editor.busy)
        editor.window!.performClose(nil)
        precondition(closed && session.overlays.isEmpty, "Cancel must work while the text is being read")
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    precondition(weakSession == nil, "Capture session leaked after canceling a text read")
    var ocrPending = false
    autoreleasepool {
        let session = ScreenCaptureSession(store: store)
        weakSession = session
        var closed = false
        session.onClose = { closed = true }
        session.present([snapshot])
        let view = session.overlays[0].contentView as! CaptureSelectionView
        drag(view, from: NSPoint(x: 195, y: 180), to: NSPoint(x: 385, y: 225))
        let editor = session.editor!
        precondition(editor.tool == .rectangle && editor.color == .systemYellow && editor.width == 9, "Tool, color and width carry over between captures")
        editor.copyText()
        // macOS prepares the OCR model once per new binary, sometimes for minutes; BolsoChecks covers recognition itself.
        wait(seconds: 20) { closed }
        if closed {
            precondition(store.items.first?.text.contains("2026") == true, "Recognized text must reach the clipboard, got: \(store.items.first?.text ?? "nada")")
        } else {
            precondition(editor.busy && !TextRecognizer.isPrepared, "Copy text must finish or still wait for the model: \(editor.message)")
            ocrPending = true
            editor.window!.performClose(nil)
            precondition(closed, "Cancel must work while the OCR model is being prepared")
        }
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    precondition(weakSession == nil, "Capture session leaked after copying text")
    print("PASS: clique captura janela, alças recortam, alça move, nova área por arrasto, trava após marcar, descarte sem diálogo, cancelar durante o OCR, arrastar para outro app e preferências")
    print(ocrPending ? "SKIP: copiar texto na captura — o macOS ainda prepara o OCR deste binário; rode de novo em alguns minutos"
                     : "PASS: copiar texto na captura vai para a área de transferência e fecha a captura")
}
