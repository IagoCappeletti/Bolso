import AppKit
import SwiftUI
import BolsoCore

/// `Bolso --render-demo <video.mp4> [--vertical] [--stills <folder>]` animates the real panel, capture overlay and
/// toolbar over a made-up desktop and pipes the frames to ffmpeg. `--vertical` makes a 4:5 cut that follows the action
/// for phones. Nothing reads the user's clipboard or preferences.
func runDemoRender() {
    setbuf(stdout, nil)
    let arguments = CommandLine.arguments
    guard let flag = arguments.firstIndex(of: "--render-demo"), arguments.count > flag + 1 else {
        print("Uso: Bolso --render-demo <video.mp4> [--vertical] [--stills <pasta>]"); exit(2)
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    app.appearance = NSAppearance(named: .darkAqua)
    isolatePreferences()
    if let icon = NSImage(contentsOfFile: "Assets/Bolso-icon.png") { app.applicationIconImage = icon }
    let stills = arguments.firstIndex(of: "--stills").flatMap { arguments.count > $0 + 1 ? URL(fileURLWithPath: arguments[$0 + 1], isDirectory: true) : nil }
    DemoVideo(output: URL(fileURLWithPath: arguments[flag + 1]), vertical: arguments.contains("--vertical"), stills: stills).render()
    exit(0)
}

private enum Bubble: Hashable {
    case text(String, mine: Bool)
    case image
}

private final class DemoVideo {
    let output: URL
    let vertical: Bool
    let stills: URL?
    /// The fictional screen; the vertical cut gets extra desktop below the windows for its captions.
    let canvas: CGSize
    let video: (width: Int, height: Int)
    let fps = 30.0
    let duration = 23.5
    /// The title stays a little longer before the first gesture.
    let lead = 0.5
    private var windows: [NSWindow] = []

    static let document = CGRect(x: 100, y: 90, width: 740, height: 560)
    static let chat = CGRect(x: 890, y: 110, width: 450, height: 660)
    static let rows = [("Código da reserva", "MZ-48213"), ("Check-in", "14/11 a partir das 14h"), ("Endereço", "Rua das Gaivotas, 85"),
                       ("Check-out", "17/11 até as 11h"), ("Café da manhã", "Incluso")]
    static let valueX: CGFloat = document.minX + 48 + 330
    static func rowTop(_ index: Int) -> CGFloat { 236 + CGFloat(index) * 44 }
    static let valueFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    static func valueWidth(_ index: Int) -> CGFloat { (rows[index].1 as NSString).size(withAttributes: [.font: valueFont]).width }
    static let input = CGRect(x: chat.minX + 16, y: chat.maxY - 54, width: chat.width - 32, height: 38)
    static let inputPoint = CGPoint(x: input.minX + 90, y: input.midY)
    /// After clicking the field the pointer drifts up, so the panel opens beside it instead of against the bottom edge.
    static let restPoint = CGPoint(x: 980, y: 330)
    static let question = "Me passa o endereço do hotel e um print da reserva?"
    static let answer = rows[2].1

    init(output: URL, vertical: Bool, stills: URL?) {
        self.output = output
        self.vertical = vertical
        self.stills = stills
        canvas = vertical ? CGSize(width: 1440, height: 1000) : CGSize(width: 1440, height: 900)
        video = vertical ? (1080, 1350) : (1920, 1200)
        display = CaptureDisplay(id: 0, frame: CGRect(origin: .zero, size: canvas), visibleFrame: CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height - 25),
                                 pixelWidth: Int(canvas.width * 2), pixelHeight: Int(canvas.height * 2))
    }

    // MARK: Timeline

    private struct Key { let time: Double; let point: CGPoint }
    private lazy var path: [Key] = {
        func row(_ index: Int) -> (CGPoint, CGPoint) {
            let y = Self.rowTop(index) + 10
            return (CGPoint(x: Self.valueX, y: y), CGPoint(x: Self.valueX + Self.valueWidth(index), y: y))
        }
        let (v0, v1) = row(2), (d0, d1) = row(0), (e0, e1) = row(3)
        let mark = Self.valueX + Self.valueWidth(2), top = Self.rowTop(2)
        return [Key(time: 0, point: CGPoint(x: 720, y: 620)), Key(time: 1.6, point: CGPoint(x: 720, y: 620)),
                Key(time: 2.3, point: v0), Key(time: 2.6, point: v1), Key(time: 2.9, point: v1),
                Key(time: 3.4, point: d0), Key(time: 3.7, point: d1), Key(time: 4.0, point: d1),
                Key(time: 4.5, point: e0), Key(time: 4.8, point: e1), Key(time: 5.1, point: e1),
                Key(time: 5.9, point: Self.inputPoint), Key(time: 6.0, point: Self.inputPoint), Key(time: 6.35, point: Self.restPoint), Key(time: 11.0, point: Self.restPoint),
                Key(time: 11.7, point: selectionStart), Key(time: 12.9, point: selectionEnd), Key(time: 13.2, point: selectionEnd),
                Key(time: 13.7, point: CGPoint(x: Self.valueX - 14, y: top - 11)),
                Key(time: 14.3, point: CGPoint(x: mark + 14, y: top + 31)), Key(time: 14.5, point: CGPoint(x: mark + 14, y: top + 31)),
                Key(time: 14.9, point: CGPoint(x: mark + 130, y: top + 110)),
                Key(time: 15.4, point: CGPoint(x: mark + 22, y: top + 36)), Key(time: 15.6, point: CGPoint(x: mark + 22, y: top + 36)),
                Key(time: 16.2, point: copyButton), Key(time: 16.5, point: copyButton),
                Key(time: 17.3, point: Self.inputPoint), Key(time: duration, point: Self.inputPoint)]
    }()
    let selectionStart = CGPoint(x: 130, y: 128)
    let selectionEnd = CGPoint(x: 832, y: 456)
    var selection: CGRect { CGRect(x: selectionStart.x, y: selectionStart.y, width: selectionEnd.x - selectionStart.x, height: selectionEnd.y - selectionStart.y) }
    let clicks: [Double] = [5.9, 16.3, 17.3]
    let keys: [(Double, String)] = [(2.7, "⌘C"), (3.8, "⌘C"), (4.9, "⌘C"), (6.3, "⇧⌘V"), (7.4, "↓"), (7.9, "↓"), (8.6, "↩"), (9.4, "↩"),
                                    (11.0, "⇧⌘2"), (17.7, "⌘V"), (18.1, "↩")]
    let captions: [(Double, Double, String)] = [(1.6, 6.1, "Copie o que precisar"), (6.2, 10.7, "⇧⌘V mostra tudo o que você copiou"),
                                                (10.8, 16.7, "⇧⌘2 tira o print e já deixa marcar"), (16.8, 19.4, "Depois é só colar")]
    /// Left edge of the vertical cut: the document while copying and capturing, the chat while pasting.
    let pans: [(Double, CGFloat)] = [(0, 70), (5.1, 70), (5.8, 640), (10.8, 640), (11.5, 90), (16.5, 90), (17.2, 640)]

    private func cursor(at t: Double) -> CGPoint {
        if t <= path[0].time { return path[0].point }
        guard let next = path.firstIndex(where: { $0.time > t }) else { return path.last!.point }
        let a = path[next - 1], b = path[next]
        let p = ease((t - a.time) / (b.time - a.time))
        return CGPoint(x: a.point.x + (b.point.x - a.point.x) * p, y: a.point.y + (b.point.y - a.point.y) * p)
    }
    private func camera(at t: Double) -> CGRect {
        guard vertical else { return CGRect(origin: .zero, size: canvas) }
        let size = CGSize(width: canvas.height * CGFloat(video.width) / CGFloat(video.height), height: canvas.height)
        var x = pans.last!.1
        if t <= pans[0].0 {
            x = pans[0].1
        } else if let next = pans.firstIndex(where: { $0.0 > t }) {
            let a = pans[next - 1], b = pans[next]
            x = a.1 + (b.1 - a.1) * ease((t - a.0) / (b.0 - a.0))
        }
        return CGRect(origin: CGPoint(x: x, y: 0), size: size)
    }
    private func ease(_ x: Double) -> CGFloat { let x = min(1, max(0, x)); return CGFloat(x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2) }
    private func ramp(_ t: Double, _ a: Double, _ b: Double) -> CGFloat { CGFloat(min(1, max(0, (t - a) / (b - a)))) }

    // MARK: Desktop

    private struct DesktopState: Hashable {
        var highlight: Int?
        var progress: Int = 0
        var input = ""
        var bubbles: [Bubble] = [.text(DemoVideo.question, mine: false)]
    }
    private var desktops: [DesktopState: CGImage] = [:]
    private var bubbleImage: CGImage?

    private func desktopState(at t: Double) -> DesktopState {
        var state = DesktopState()
        let selections: [(Int, Double, Double, Double)] = [(2, 2.3, 2.6, 3.4), (0, 3.4, 3.7, 4.5), (3, 4.5, 4.8, 5.9)]
        if let s = selections.first(where: { t >= $0.1 && t < $0.3 }) {
            state.highlight = s.0
            state.progress = Int(ramp(t, s.1, s.2) * 20)
        }
        if t >= 8.75 && t < 9.4 { state.input = Self.answer }
        if t >= 9.4 { state.bubbles.append(.text(Self.answer, mine: true)) }
        if t >= 18.1 { state.bubbles.append(.image) }
        return state
    }
    private func desktop(_ state: DesktopState) -> CGImage {
        if let cached = desktops[state] { return cached }
        let image = drawDesktop(state)
        desktops[state] = image
        return image
    }

    private func drawDesktop(_ state: DesktopState) -> CGImage {
        let size = canvas
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        func box(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: size.height - r.minY - r.height, width: r.width, height: r.height) }
        func text(_ string: String, _ x: CGFloat, _ top: CGFloat, font: NSFont, color: NSColor = .black, width: CGFloat = 640) {
            (string as NSString).draw(in: box(CGRect(x: x, y: top, width: width, height: font.pointSize * 3.2)), withAttributes: [.font: font, .foregroundColor: color])
        }
        NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.29, blue: 0.45, alpha: 1), ending: NSColor(srgbRed: 0.45, green: 0.33, blue: 0.52, alpha: 1))!
            .draw(in: CGRect(origin: .zero, size: size), angle: 35)
        NSColor(white: 1, alpha: 0.28).setFill(); box(CGRect(x: 0, y: 0, width: size.width, height: 24)).fill()
        text("Arquivo    Editar    Visualizar    Janela    Ajuda", 16, 4, font: .systemFont(ofSize: 13, weight: .medium), color: NSColor(white: 0.1, alpha: 1))
        for (frame, title) in [(Self.document, "Reserva-Mar-Azul.pdf"), (Self.chat, "Conversa")] {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -8); shadow.shadowColor = NSColor(white: 0, alpha: 0.35); shadow.set()
            NSColor.white.setFill()
            NSBezierPath(roundedRect: box(frame), xRadius: 12, yRadius: 12).fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor(white: 0.93, alpha: 1).setFill(); NSBezierPath(roundedRect: box(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 36)), xRadius: 12, yRadius: 12).fill()
            for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                color.setFill(); NSBezierPath(ovalIn: box(CGRect(x: frame.minX + 16 + CGFloat(index) * 20, y: frame.minY + 12, width: 12, height: 12))).fill()
            }
            text(title, frame.minX + 90, frame.minY + 10, font: .systemFont(ofSize: 13, weight: .semibold), color: NSColor(white: 0.25, alpha: 1), width: frame.width - 120)
        }
        let left = Self.document.minX + 48
        text("CONFIRMAÇÃO DA RESERVA", left, 140, font: .systemFont(ofSize: 22, weight: .bold))
        text("Hotel Mar Azul · Florianópolis/SC · 3 noites, 2 adultos", left, 182, font: .systemFont(ofSize: 15), color: NSColor(white: 0.3, alpha: 1))
        for (index, row) in Self.rows.enumerated() {
            let top = Self.rowTop(index)
            NSColor(white: index.isMultiple(of: 2) ? 0.965 : 1, alpha: 1).setFill(); box(CGRect(x: left - 12, y: top - 10, width: 660, height: 40)).fill()
            if state.highlight == index {
                NSColor(srgbRed: 0.70, green: 0.83, blue: 1, alpha: 1).setFill()
                box(CGRect(x: Self.valueX - 2, y: top - 2, width: (Self.valueWidth(index) + 4) * CGFloat(state.progress) / 20, height: 22)).fill()
            }
            text(row.0, left, top, font: .systemFont(ofSize: 15), color: NSColor(white: 0.35, alpha: 1), width: 300)
            text(row.1, Self.valueX, top, font: Self.valueFont, width: 300)
        }
        text("Apresente um documento com foto no check-in.", left, 480, font: .systemFont(ofSize: 14), color: NSColor(white: 0.4, alpha: 1))
        text("Cancelamento grátis até 48 horas antes da chegada.", left, 504, font: .systemFont(ofSize: 14), color: NSColor(white: 0.4, alpha: 1))

        let chat = Self.chat
        var top = chat.minY + 60
        let bubbleFont = NSFont.systemFont(ofSize: 14)
        for bubble in state.bubbles {
            switch bubble {
            case .text(let string, let mine):
                let bounds = (string as NSString).boundingRect(with: CGSize(width: 238, height: 400), options: [.usesLineFragmentOrigin], attributes: [.font: bubbleFont])
                let width = ceil(bounds.width) + 32, height = ceil(bounds.height) + 22
                let x = mine ? chat.maxX - width - 20 : chat.minX + 20
                (mine ? NSColor(srgbRed: 0.20, green: 0.52, blue: 0.98, alpha: 1) : NSColor(white: 0.92, alpha: 1)).setFill()
                NSBezierPath(roundedRect: box(CGRect(x: x, y: top, width: width, height: height)), xRadius: 18, yRadius: 18).fill()
                text(string, x + 16, top + 11, font: bubbleFont, color: mine ? .white : .black, width: width - 30)
                top += height + 12
            case .image:
                guard let image = bubbleImage else { continue }
                let width: CGFloat = 300, height = width * CGFloat(image.height) / CGFloat(image.width)
                let frame = box(CGRect(x: chat.maxX - width - 20, y: top, width: width, height: height))
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: frame, xRadius: 14, yRadius: 14).addClip()
                NSImage(cgImage: image, size: frame.size).draw(in: frame)
                NSGraphicsContext.restoreGraphicsState()
                NSColor(white: 0, alpha: 0.12).setStroke()
                let border = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14); border.lineWidth = 1; border.stroke()
                top += height + 12
            }
        }
        NSColor(white: 0.97, alpha: 1).setFill()
        let field = NSBezierPath(roundedRect: box(Self.input), xRadius: 19, yRadius: 19); field.fill()
        NSColor(white: 0.82, alpha: 1).setStroke(); field.lineWidth = 1; field.stroke()
        if state.input.isEmpty {
            text("Mensagem", Self.input.minX + 16, Self.input.minY + 10, font: bubbleFont, color: NSColor(white: 0.6, alpha: 1), width: 300)
        } else {
            text(state.input, Self.input.minX + 16, Self.input.minY + 10, font: bubbleFont, width: 300)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    // MARK: App screens

    private var panels: [CGImage] = []
    private var overlay: CaptureSelectionView!
    private var overlayWindow: NSWindow!
    private var editor: ImageEditorSession!
    private var markup: ImageEditorDocument!
    private var bar: NSView!
    private var barImage: CGImage?
    private var barFrame = CGRect.zero
    private var copyButton = CGPoint.zero
    private let display: CaptureDisplay

    private func preparePanels() {
        let board = NSPasteboard.withUniqueName()
        let store = ClipboardStore(board: board)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Reserva-Mar-Azul.pdf")
        try? Data("%PDF-1.4\n".utf8).write(to: file)
        let crop = desktop(DesktopState()).cropping(to: CGRect(x: 200, y: 180, width: 1440, height: 1040))!
        let samples: [(NSPasteboard) -> Void] = [
            { $0.setData(NSBitmapImageRep(cgImage: crop).representation(using: .png, properties: [:])!, forType: .png) },
            { $0.writeObjects([file as NSURL]) },
            { $0.setString("https://github.com/IagoCappeletti/Bolso", forType: .string) },
            { $0.setString(Self.rows[2].1, forType: .string) },
            { $0.setString(Self.rows[0].1, forType: .string) },
            { $0.setString(Self.rows[3].1, forType: .string) },
        ]
        for write in samples {
            board.clearContents(); write(board)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
        }
        let session = PanelSession(store: store)
        let view = host(HistoryView(session: session, store: store), size: CGSize(width: 410, height: 480))
        for index in 0..<3 {
            session.selection = index
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            panels.append(image(of: view)!.cgImage!)
        }
        board.releaseGlobally()
    }

    private func prepareCapture() {
        var snapshot = CapturedDisplay(display: display, image: desktop(desktopState(at: 11)))
        snapshot.windows = [Self.document, Self.chat]
        overlay = CaptureSelectionView(snapshot: snapshot)
        overlayWindow = CaptureOverlayWindow(contentRect: display.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        windows.append(overlayWindow)
        overlayWindow.contentView = overlay
        let pixels = CaptureGeometry.pixelRect(for: selection, displaySize: display.frame.size, imageSize: CGSize(width: display.pixelWidth, height: display.pixelHeight))!
        markup = ImageEditorDocument(image: snapshot.image.cropping(to: pixels)!)
        let store = ClipboardStore(board: NSPasteboard.withUniqueName())
        store.togglePause()
        let toolbar = CaptureToolbarPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        windows.append(toolbar)
        editor = ImageEditorSession(document: markup, toolbar: toolbar, canvasWindow: overlayWindow, store: store)
        bar = host(CaptureToolbarView(editor: editor, document: markup), width: min(720, display.visibleFrame.width))
        let global = CaptureGeometry.toolbarFrame(size: bar.bounds.size, selection: CaptureGeometry.globalRect(for: selection, screenFrame: display.frame), visibleFrame: display.visibleFrame)
        barFrame = CGRect(x: global.minX - display.frame.minX, y: display.frame.maxY - global.maxY, width: global.width, height: global.height)
        copyButton = CGPoint(x: barFrame.maxX - 42, y: barFrame.minY + 66)
    }

    private func refreshBar() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        barImage = image(of: bar)?.cgImage
    }

    private func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: overlay.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: overlayWindow.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    /// Fires the gestures due by `t`, in order, the way the user's hand would.
    private var done = Set<String>()
    private func act(at t: Double, cursor point: CGPoint) {
        func once(_ name: String, _ time: Double, _ action: () -> Void) {
            guard t >= time, !done.contains(name) else { return }
            done.insert(name); action()
        }
        guard t >= 11 && t < 16.6 else { return }
        if t < 11.7 { overlay.updateHover(at: point) }
        once("select-down", 11.7) {
            overlay.mouseDown(with: mouse(.leftMouseDown, selectionStart))
            // mouseDown brings the overlay forward; it must never cover the real screen.
            overlayWindow.orderOut(nil)
        }
        if t >= 11.7 && t < 12.9 { overlay.mouseDragged(with: mouse(.leftMouseDragged, point)) }
        once("select-up", 12.9) {
            overlay.mouseUp(with: mouse(.leftMouseUp, selectionEnd))
            overlay.beginEditing(rect: selection, editor: editor, document: markup)
            refreshBar()
        }
        once("tool-box", 13.2) { editor.tool = .rectangle; refreshBar() }
        once("box-down", 13.7) { overlay.canvas?.mouseDown(with: mouse(.leftMouseDown, point)) }
        if t >= 13.7 && t < 14.3 { overlay.canvas?.mouseDragged(with: mouse(.leftMouseDragged, point)) }
        once("box-up", 14.3) { overlay.canvas?.mouseUp(with: mouse(.leftMouseUp, point)); refreshBar() }
        once("tool-arrow", 14.5) { editor.tool = .arrow; refreshBar() }
        once("arrow-down", 14.9) { overlay.canvas?.mouseDown(with: mouse(.leftMouseDown, point)) }
        if t >= 14.9 && t < 15.4 { overlay.canvas?.mouseDragged(with: mouse(.leftMouseDragged, point)) }
        once("arrow-up", 15.4) { overlay.canvas?.mouseUp(with: mouse(.leftMouseUp, point)); refreshBar() }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
    }

    // MARK: Frames

    func render() {
        preparePanels()
        prepareCapture()
        let ffmpeg = Process()
        ffmpeg.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        ffmpeg.arguments = ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "bgra", "-s", "\(video.width)x\(video.height)", "-r", "\(Int(fps))", "-i", "-",
                            "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart", output.path]
        let pipe = Pipe()
        ffmpeg.standardInput = pipe
        do { try ffmpeg.run() } catch { print("FAIL: ffmpeg não encontrado (brew install ffmpeg)"); exit(1) }
        let context = CGContext(data: nil, width: video.width, height: video.height, bitsPerComponent: 8, bytesPerRow: video.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        context.translateBy(x: 0, y: CGFloat(video.height)); context.scaleBy(x: 1, y: -1)
        let stillTimes: [Double] = [0.8, 2.75, 5.5, 7.0, 8.0, 9.8, 11.4, 12.4, 13.5, 14.1, 15.5, 16.25, 18.6, 21.5]
        if let stills {
            try? FileManager.default.createDirectory(at: stills, withIntermediateDirectories: true)
            try? NSBitmapImageRep(cgImage: panels[0]).representation(using: .png, properties: [:])?.write(to: stills.appendingPathComponent("painel.png"))
        }
        var overlayImage: CGImage?
        let frames = Int((duration + lead) * fps)
        for index in 0..<frames {
            let t = Double(index) / fps - lead
            let point = cursor(at: t)
            act(at: t, cursor: point)
            if t >= 11 && t < 16.6 { overlayImage = image(of: overlay)?.cgImage }
            if bubbleImage == nil, t >= 16.25, let overlayImage {
                bubbleImage = overlayImage.cropping(to: CGRect(x: selection.minX * 2, y: selection.minY * 2, width: selection.width * 2, height: selection.height * 2))
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            let view = camera(at: t)
            context.saveGState()
            context.scaleBy(x: CGFloat(video.width) / view.width, y: CGFloat(video.height) / view.height)
            context.translateBy(x: -view.minX, y: -view.minY)
            compose(t: t, cursor: point, overlay: overlayImage, in: context)
            context.restoreGState()
            context.saveGState()
            context.scaleBy(x: CGFloat(video.width) / view.width, y: CGFloat(video.height) / view.height)
            drawChrome(t: t, size: view.size, in: context)
            context.restoreGState()
            NSGraphicsContext.restoreGraphicsState()
            pipe.fileHandleForWriting.write(Data(bytesNoCopy: context.data!, count: video.width * video.height * 4, deallocator: .none))
            if let stills, let still = stillTimes.first(where: { abs($0 - t) < 0.5 / fps }), let frame = context.makeImage() {
                try? NSBitmapImageRep(cgImage: frame).representation(using: .png, properties: [:])?.write(to: stills.appendingPathComponent(String(format: "%05.2f.png", still)))
            }
            if index % 90 == 0 { print("  \(index / 30) s") }
        }
        pipe.fileHandleForWriting.closeFile()
        ffmpeg.waitUntilExit()
        print(ffmpeg.terminationStatus == 0 ? "PASS: \(output.path)" : "FAIL: ffmpeg \(ffmpeg.terminationStatus)")
    }

    private func draw(_ image: CGImage, in rect: CGRect, alpha: CGFloat = 1, in c: CGContext) {
        c.saveGState()
        c.setAlpha(alpha)
        c.translateBy(x: rect.minX, y: rect.maxY); c.scaleBy(x: 1, y: -1)
        c.draw(image, in: CGRect(origin: .zero, size: rect.size))
        c.restoreGState()
    }

    /// The screen itself, in screen points; the camera decides which part reaches the video.
    private func compose(t: Double, cursor point: CGPoint, overlay: CGImage?, in c: CGContext) {
        let full = CGRect(origin: .zero, size: canvas)
        // A new chat bubble fades in over the previous state.
        draw(desktop(desktopState(at: t)), in: full, in: c)
        for change in [9.4, 18.1] where t >= change && t < change + 0.2 {
            draw(desktop(desktopState(at: change - 0.01)), in: full, alpha: 1 - ramp(t, change, change + 0.2), in: c)
        }

        if t >= 6.4 && t < 8.75 {
            let alpha = min(ramp(t, 6.4, 6.55), 1 - ramp(t, 8.6, 8.75))
            let scale = 0.97 + 0.03 * alpha
            let panel = panels[t < 7.4 ? 0 : t < 7.9 ? 1 : 2]
            let origin = CGPoint(x: min(Self.restPoint.x + 12, canvas.width - 410), y: min(Self.restPoint.y + 12, canvas.height - 480))
            let rect = CGRect(x: origin.x + 205 * (1 - scale), y: origin.y, width: 410 * scale, height: 480 * scale)
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: -12), blur: 36, color: NSColor(white: 0, alpha: 0.5 * alpha).cgColor)
            draw(panel, in: rect, alpha: alpha, in: c)
            c.restoreGState()
        }

        if t >= 11 && t < 16.5, let overlay {
            let alpha = min(ramp(t, 11, 11.12), 1 - ramp(t, 16.35, 16.5))
            draw(overlay, in: full, alpha: alpha, in: c)
            if t >= 12.9, let barImage {
                draw(barImage, in: barFrame, alpha: min(alpha, ramp(t, 12.9, 13.05)), in: c)
            }
        }

        let cursorAlpha = 1 - ramp(t, 19.6, 20.0)
        for click in clicks where t >= click && t < click + 0.35 {
            let p = CGFloat((t - click) / 0.35)
            let radius = 8 + 18 * p
            c.setStrokeColor(NSColor(white: 1, alpha: 0.8 * (1 - p)).cgColor)
            c.setLineWidth(3)
            c.strokeEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
        let crosshair = (t >= 11 && t < 15.5)
        let image = crosshair ? NSCursor.crosshair.image : NSCursor.arrow.image
        let hotSpot = crosshair ? NSCursor.crosshair.hotSpot : NSCursor.arrow.hotSpot
        let scale: CGFloat = 1.4
        image.draw(in: CGRect(x: point.x - hotSpot.x * scale, y: point.y - hotSpot.y * scale, width: image.size.width * scale, height: image.size.height * scale),
                   from: .zero, operation: .sourceOver, fraction: cursorAlpha, respectFlipped: true, hints: nil)
    }

    /// Captions, keys and title cards, laid out on the visible frame so they stay put while the camera pans.
    private func drawChrome(t: Double, size: CGSize, in c: CGContext) {
        drawCaption(t: t, size: size)
        drawKey(t: t, size: size, in: c)
        let intro = 1 - ramp(t, 1.25, 1.6)
        if intro > 0 { drawCard(alpha: intro, size: size, lines: ["Histórico do que você copia", "e print com marcação, pro Mac"], link: nil) }
        let end = ramp(t, 19.6, 20.0)
        if end > 0 { drawCard(alpha: end, size: size, lines: ["Grátis, pro Mac"], link: "github.com/IagoCappeletti/Bolso") }
    }

    private func drawCaption(t: Double, size: CGSize) {
        guard let caption = captions.first(where: { t >= $0.0 && t < $0.1 }) else { return }
        let alpha = min(ramp(t, caption.0, caption.0 + 0.2), 1 - ramp(t, caption.1 - 0.2, caption.1))
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: NSColor(white: 1, alpha: alpha)]
        let text = (caption.2 as NSString).size(withAttributes: attributes)
        let pill = CGRect(x: (size.width - text.width) / 2 - 26, y: size.height - 78, width: text.width + 52, height: text.height + 22)
        NSColor(white: 0.05, alpha: 0.78 * alpha).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        (caption.2 as NSString).draw(at: CGPoint(x: pill.minX + 26, y: pill.minY + 11), withAttributes: attributes)
    }

    private func drawKey(t: Double, size: CGSize, in c: CGContext) {
        guard let key = keys.last(where: { t >= $0.0 && t < $0.0 + 0.7 }) else { return }
        let age = t - key.0
        let alpha = min(ramp(age, 0, 0.08), 1 - ramp(age, 0.55, 0.7))
        let pop = 1 + 0.08 * (1 - ramp(age, 0, 0.15))
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 34 * pop, weight: .semibold), .foregroundColor: NSColor(white: 0.12, alpha: alpha)]
        let text = (key.1 as NSString).size(withAttributes: attributes)
        let width = max(text.width + 40, 70 * pop), height = 62 * pop
        let cap = CGRect(x: (size.width - width) / 2, y: size.height - 152 - (height - 62) / 2, width: width, height: height)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -3), blur: 10, color: NSColor(white: 0, alpha: 0.35 * alpha).cgColor)
        NSColor(white: 0.97, alpha: alpha).setFill()
        NSBezierPath(roundedRect: cap, xRadius: 12, yRadius: 12).fill()
        c.restoreGState()
        (key.1 as NSString).draw(at: CGPoint(x: cap.midX - text.width / 2, y: cap.midY - text.height / 2), withAttributes: attributes)
    }

    private func drawCard(alpha: CGFloat, size: CGSize, lines: [String], link: String?) {
        NSColor(white: 0.04, alpha: 0.74 * alpha).setFill()
        CGRect(origin: .zero, size: size).fill()
        var top = size.height / 2 - 200
        NSApp.applicationIconImage.draw(in: CGRect(x: size.width / 2 - 60, y: top, width: 120, height: 120), from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
        top += 142
        let entries = [("Bolso", NSFont.systemFont(ofSize: 58, weight: .bold), CGFloat(1))] + lines.map { ($0, NSFont.systemFont(ofSize: 26), CGFloat(0.86)) }
            + (link.map { [($0, NSFont.systemFont(ofSize: 26, weight: .semibold), CGFloat(0.86))] } ?? [])
        for (index, entry) in entries.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [.font: entry.1, .foregroundColor: NSColor(white: 1, alpha: entry.2 * alpha)]
            let text = (entry.0 as NSString).size(withAttributes: attributes)
            (entry.0 as NSString).draw(at: CGPoint(x: (size.width - text.width) / 2, y: top), withAttributes: attributes)
            top += text.height + (index == 0 ? 14 : 6)
        }
    }

    // MARK: Hosting

    private func host<V: View>(_ root: V, size: CGSize? = nil, width: CGFloat? = nil) -> NSView {
        let hosting = NSHostingView(rootView: root)
        var fitting = size ?? hosting.fittingSize
        if let width { fitting = CGSize(width: width, height: NSHostingController(rootView: root).sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height) }
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: fitting), styleMask: [.borderless], backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: .darkAqua)
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
}
