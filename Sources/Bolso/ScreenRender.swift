import AppKit
import SwiftUI
import BolsoCore

/// `Bolso --render-screens <folder>` draws every screen offscreen with sample content, for design reviews.
/// It never reads the user's clipboard or preferences and puts nothing on screen.
func runScreenRender() {
    setbuf(stdout, nil)
    let arguments = CommandLine.arguments
    guard let flag = arguments.firstIndex(of: "--render-screens"), arguments.count > flag + 1 else {
        print("Uso: Bolso --render-screens <pasta>"); exit(2)
    }
    let folder = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    isolatePreferences()
    if let icon = NSImage(contentsOfFile: "Assets/Bolso-icon.png") { app.applicationIconImage = icon }
    let renderer = ScreenRenderer(folder: folder)
    for appearance in [NSAppearance.Name.darkAqua, .aqua] { renderer.renderAll(appearance: appearance) }
    print("PASS: \(renderer.count) telas em \(folder.path)")
}

private final class ScreenRenderer {
    let folder: URL
    private(set) var count = 0
    private var windows: [NSWindow] = []
    private let screen = SampleScreen.make()
    init(folder: URL) { self.folder = folder }

    func renderAll(appearance: NSAppearance.Name) {
        let suffix = appearance == .darkAqua ? "escuro" : "claro"
        renderPanels(suffix: suffix, appearance: appearance)
        renderCapture(suffix: suffix, appearance: appearance)
        renderEditor(suffix: suffix, appearance: appearance)
        renderAlerts(suffix: suffix, appearance: appearance)
    }

    // MARK: History panel

    private func renderPanels(suffix: String, appearance: NSAppearance.Name) {
        let board = NSPasteboard.withUniqueName()
        let store = ClipboardStore(board: board)
        let document = FileManager.default.temporaryDirectory.appendingPathComponent("Edital-12-2026.pdf")
        try? Data("%PDF-1.4\n".utf8).write(to: document)
        let crop = screen.cropping(to: CGRect(x: 240, y: 180, width: 1440, height: 1040))!
        let samples: [(NSPasteboard) -> Void] = [
            { $0.setString("CNPJ 12.345.678/0001-90 — Rua das Flores, 120, São Paulo/SP", forType: .string) },
            { $0.setString("swift build -c release --product Bolso", forType: .string) },
            { $0.writeObjects([document as NSURL]) },
            { $0.setString("https://github.com/IagoCappeletti/Bolso/releases/latest", forType: .string) },
            { $0.setData(NSBitmapImageRep(cgImage: crop).representation(using: .png, properties: [:])!, forType: .png) },
            { $0.setString("Proposta enviada. Valor final de R$ 182.900,00 com entrega em 15 dias úteis, conforme o edital.", forType: .string) },
        ]
        for write in samples {
            board.clearContents(); write(board)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
        }
        let session = PanelSession(store: store)
        save(host(HistoryView(session: session, store: store), size: CGSize(width: 410, height: 480), appearance: appearance), "historico-\(suffix)")
        store.togglePause()
        save(host(HistoryView(session: session, store: store), size: CGSize(width: 410, height: 480), appearance: appearance), "historico-pausado-\(suffix)")
        store.togglePause()
        let empty = ClipboardStore(board: NSPasteboard.withUniqueName())
        save(host(HistoryView(session: PanelSession(store: empty), store: empty), size: CGSize(width: 410, height: 480), appearance: appearance), "historico-vazio-\(suffix)")
        board.releaseGlobally()
    }

    // MARK: Capture

    private func renderCapture(suffix: String, appearance: NSAppearance.Name) {
        let display = CaptureDisplay(id: 0, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875), pixelWidth: 2880, pixelHeight: 1800)
        var snapshot = CapturedDisplay(display: display, image: screen)
        snapshot.windows = [SampleScreen.document, SampleScreen.chat]

        let hovering = CaptureSelectionView(snapshot: snapshot)
        let hoverHost = window(for: hovering, frame: display.frame, appearance: appearance)
        hoverHost.contentView = hovering
        hovering.updateHover(at: CGPoint(x: SampleScreen.document.midX, y: SampleScreen.document.midY))
        save(hovering, "captura-janela-\(suffix)")

        let dragging = CaptureSelectionView(snapshot: snapshot)
        let dragHost = window(for: dragging, frame: display.frame, appearance: appearance)
        dragHost.contentView = dragging
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: dragging.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: dragHost.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        dragging.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 160, y: 150)))
        dragging.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 720, y: 430)))
        dragHost.orderOut(nil)
        save(dragging, "captura-arrastando-\(suffix)")

        let store = ClipboardStore(board: NSPasteboard.withUniqueName())
        store.togglePause()
        let selection = CGRect(x: 160, y: 150, width: 560, height: 280)
        let pixels = CaptureGeometry.pixelRect(for: selection, displaySize: display.frame.size, imageSize: CGSize(width: 2880, height: 1800))!
        let document = ImageEditorDocument(image: screen.cropping(to: pixels)!)
        let view = CaptureSelectionView(snapshot: snapshot)
        let overlay = window(for: view, frame: display.frame, appearance: appearance)
        overlay.contentView = view
        let toolbar = CaptureToolbarPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        windows.append(toolbar)
        let editor = ImageEditorSession(document: document, toolbar: toolbar, canvasWindow: overlay, store: store)
        view.beginEditing(rect: selection, editor: editor, document: document)
        let bar = host(CaptureToolbarView(editor: editor, document: document), width: min(720, display.visibleFrame.width), appearance: appearance)
        saveComposite(view, bar, selection: selection, display: display, name: "captura-ajuste-\(suffix)")

        document.add(Annotation(tool: .rectangle, points: [CGPoint(x: 60, y: 120), CGPoint(x: 700, y: 260)], color: .systemRed, width: 6))
        document.add(Annotation(tool: .arrow, points: [CGPoint(x: 900, y: 420), CGPoint(x: 720, y: 250)], color: .systemRed, width: 6))
        document.add(Annotation(tool: .counter, points: [CGPoint(x: 1010, y: 440)], color: .systemRed, width: 6, number: 1))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        saveComposite(view, bar, selection: selection, display: display, name: "captura-marcada-\(suffix)")
        save(bar, "captura-barra-\(suffix)")
        save(host(CustomColorPicker(selected: NSColor(srgbRed: 0.1, green: 0.6, blue: 0.9, alpha: 1)) { _ in }, appearance: appearance), "captura-cores-\(suffix)")
        editor.confirmingDiscard = true
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        save(bar, "captura-barra-descartar-\(suffix)")
        editor.confirmingDiscard = false
    }

    // MARK: Editor

    private func renderEditor(suffix: String, appearance: NSAppearance.Name) {
        let store = ClipboardStore(board: NSPasteboard.withUniqueName())
        store.togglePause()
        let crop = screen.cropping(to: CGRect(x: 240, y: 180, width: 1440, height: 1040))!
        let payload = ImagePayload(data: NSBitmapImageRep(cgImage: crop).representation(using: .png, properties: [:])!)!
        let session = ImageEditorSession(image: payload, store: store)
        guard let window = session.window else { return }
        window.appearance = NSAppearance(named: appearance)
        window.setContentSize(NSSize(width: 1040, height: 760))
        windows.append(window)
        let timeout = Date(timeIntervalSinceNow: 5)
        while session.busy && Date() < timeout { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
        if let document = session.document {
            document.add(Annotation(tool: .highlighter, points: [CGPoint(x: 120, y: 330), CGPoint(x: 900, y: 330)], color: .systemYellow, width: 8))
            document.add(Annotation(tool: .rectangle, points: [CGPoint(x: 90, y: 520), CGPoint(x: 1000, y: 640)], color: .systemRed, width: 6))
            document.add(Annotation(tool: .text, points: [CGPoint(x: 1050, y: 580)], color: .systemRed, width: 6, text: "Conferir valor", fontSize: 40, background: true))
        }
        session.tool = .rectangle
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        if let frame = window.contentView?.superview { save(frame, "editor-\(suffix)") }
        window.contentView = nil
    }

    // MARK: Alerts

    private func renderAlerts(suffix: String, appearance: NSAppearance.Name) {
        let alerts: [(String, NSAlert)] = [
            ("aviso-atualizacao", Alerts.restart(version: "1.4.0")),
            ("aviso-acessibilidade", Alerts.accessibility()),
            ("aviso-gravacao", Alerts.capturePermission()),
            ("aviso-descartar", Alerts.discardEdits()),
        ]
        for (name, alert) in alerts {
            // An unbundled render process has no app icon of its own.
            alert.icon = NSApp.applicationIconImage
            alert.window.appearance = NSAppearance(named: appearance)
            alert.layout()
            windows.append(alert.window)
            if let frame = alert.window.contentView?.superview { save(frame, "\(name)-\(suffix)") }
        }
    }

    // MARK: Drawing

    private func window(for view: NSView, frame: CGRect, appearance: NSAppearance.Name) -> NSWindow {
        let window = CaptureOverlayWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: appearance)
        windows.append(window)
        return window
    }
    private func host<V: View>(_ root: V, size: CGSize? = nil, width: CGFloat? = nil, appearance: NSAppearance.Name) -> NSView {
        let hosting = NSHostingView(rootView: root)
        var fitting = size ?? hosting.fittingSize
        if let width { fitting = CGSize(width: width, height: NSHostingController(rootView: root).sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height) }
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: fitting), styleMask: [.borderless], backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: appearance)
        window.isOpaque = false
        window.backgroundColor = .clear
        hosting.frame = CGRect(origin: .zero, size: fitting)
        window.contentView = hosting
        windows.append(window)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        return hosting
    }
    private func image(of view: NSView) -> NSBitmapImageRep? {
        view.layoutSubtreeIfNeeded()
        view.needsDisplay = true
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }
    private func save(_ view: NSView, _ name: String) {
        guard let rep = image(of: view) else { print("  falhou: \(name)"); return }
        write(rep, name)
    }
    /// The toolbar floats beside the selection, as the session places it on a real display.
    private func saveComposite(_ overlay: NSView, _ bar: NSView, selection: CGRect, display: CaptureDisplay, name: String) {
        guard let base = image(of: overlay), let barImage = image(of: bar) else { print("  falhou: \(name)"); return }
        let frame = CaptureGeometry.toolbarFrame(size: bar.bounds.size, selection: CaptureGeometry.globalRect(for: selection, screenFrame: display.frame), visibleFrame: display.visibleFrame)
        let result = NSImage(size: display.frame.size)
        result.lockFocus()
        base.draw(in: CGRect(origin: .zero, size: display.frame.size))
        barImage.draw(in: CGRect(x: frame.minX - display.frame.minX, y: frame.minY - display.frame.minY, width: frame.width, height: frame.height))
        result.unlockFocus()
        guard let tiff = result.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
        write(rep, name)
    }
    private func write(_ rep: NSBitmapImageRep, _ name: String) {
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: folder.appendingPathComponent(name + ".png"))
        count += 1
        print("  \(name).png  \(rep.pixelsWide)×\(rep.pixelsHigh)")
    }
}

/// A fictional desktop: an invitation to bid and a chat, both made up.
private enum SampleScreen {
    static let document = CGRect(x: 120, y: 90, width: 720, height: 520)
    static let chat = CGRect(x: 900, y: 160, width: 400, height: 470)

    static func make() -> CGImage {
        let size = CGSize(width: 1440, height: 900)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2880, pixelsHigh: 1800, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        func box(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: size.height - top - h, width: w, height: h) }
        func text(_ string: String, _ x: CGFloat, _ top: CGFloat, size points: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .black, width: CGFloat = 640) {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: points, weight: weight), .foregroundColor: color]
            (string as NSString).draw(in: box(x, top, width, points * 1.5), withAttributes: attributes)
        }
        NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.29, blue: 0.45, alpha: 1), ending: NSColor(srgbRed: 0.45, green: 0.33, blue: 0.52, alpha: 1))!
            .draw(in: CGRect(origin: .zero, size: size), angle: 35)
        NSColor(white: 1, alpha: 0.28).setFill(); box(0, 0, size.width, 24).fill()
        text("Arquivo    Editar    Visualizar    Janela    Ajuda", 16, 4, size: 13, weight: .medium, color: NSColor(white: 0.1, alpha: 1))
        for (frame, title) in [(document, "Edital-12-2026.pdf"), (chat, "Conversa")] {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -8); shadow.shadowColor = NSColor(white: 0, alpha: 0.35); shadow.set()
            NSColor.white.setFill()
            NSBezierPath(roundedRect: box(frame.minX, frame.minY, frame.width, frame.height), xRadius: 12, yRadius: 12).fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor(white: 0.93, alpha: 1).setFill(); NSBezierPath(roundedRect: box(frame.minX, frame.minY, frame.width, 36), xRadius: 12, yRadius: 12).fill()
            for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                color.setFill(); NSBezierPath(ovalIn: box(frame.minX + 16 + CGFloat(index) * 20, frame.minY + 12, 12, 12)).fill()
            }
            text(title, frame.minX + 90, frame.minY + 10, size: 13, weight: .semibold, color: NSColor(white: 0.25, alpha: 1), width: frame.width - 120)
        }
        let left = document.minX + 48
        text("PREGÃO ELETRÔNICO Nº 12/2026", left, 140, size: 22, weight: .bold)
        text("Objeto: aquisição de material de escritório para as unidades regionais", left, 182, size: 15, color: NSColor(white: 0.3, alpha: 1))
        let rows = [("Abertura das propostas", "04/11/2026 às 09h"), ("Modalidade", "Menor preço por item"), ("Valor estimado", "R$ 184.350,00"), ("Entrega", "15 dias úteis"), ("Garantia", "12 meses")]
        for (index, row) in rows.enumerated() {
            let top = 236 + CGFloat(index) * 44
            NSColor(white: index.isMultiple(of: 2) ? 0.965 : 1, alpha: 1).setFill(); box(left - 12, top - 10, 640, 40).fill()
            text(row.0, left, top, size: 15, color: NSColor(white: 0.35, alpha: 1), width: 300)
            text(row.1, left + 330, top, size: 15, weight: .semibold, width: 300)
        }
        text("As propostas devem ser enviadas pelo sistema até a data de abertura.", left, 480, size: 14, color: NSColor(white: 0.4, alpha: 1))
        text("Dúvidas pelo canal oficial de esclarecimentos do órgão.", left, 504, size: 14, color: NSColor(white: 0.4, alpha: 1))
        let bubbles: [(String, Bool)] = [("Conseguiu ver o valor estimado?", false), ("Vi sim, R$ 184 mil", true), ("Manda o print da tabela?", false), ("Mando já", true)]
        for (index, bubble) in bubbles.enumerated() {
            let top = chat.minY + 64 + CGFloat(index) * 64
            let width: CGFloat = 230
            let x = bubble.1 ? chat.maxX - width - 20 : chat.minX + 20
            (bubble.1 ? NSColor(srgbRed: 0.20, green: 0.52, blue: 0.98, alpha: 1) : NSColor(white: 0.92, alpha: 1)).setFill()
            NSBezierPath(roundedRect: box(x, top, width, 44), xRadius: 18, yRadius: 18).fill()
            text(bubble.0, x + 16, top + 12, size: 14, color: bubble.1 ? .white : .black, width: width - 24)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
}
