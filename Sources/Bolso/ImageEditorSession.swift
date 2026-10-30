import AppKit
import Combine
import SwiftUI
import BolsoCore
import UniformTypeIdentifiers

final class ImageEditorSession: NSObject, ObservableObject, NSWindowDelegate {
    static let palette: [(String, NSColor)] = [("Vermelho", .systemRed), ("Amarelo", .systemYellow), ("Roxo", .systemPurple), ("Verde", .systemGreen), ("Branco", .white), ("Preto", .black)]
    /// Formatting carries over between editors and captures; typed text never does.
    static var preferences = UserDefaults.standard
    @Published var document: ImageEditorDocument?
    @Published var tool: AnnotationTool = .pen { didSet { Self.preferences.set(tool.rawValue, forKey: "editor.tool") } }
    @Published var color = NSColor.systemRed { didSet { Self.preferences.set(Self.name(of: color), forKey: "editor.color") } }
    @Published var width: Double = 5 { didSet { Self.preferences.set(width, forKey: "editor.width") } }
    @Published var text = ""
    @Published var fontSize: Double = 28 { didSet { Self.preferences.set(fontSize, forKey: "editor.fontSize") } }
    @Published var textBackground = false { didSet { Self.preferences.set(textBackground, forKey: "editor.textBackground") } }
    @Published var busy = true
    @Published var message = "Carregando imagem…"
    @Published var confirmingDiscard = false
    @Published var pickingColor = false
    @Published private(set) var recognizing = false
    var onClose: (() -> Void)?
    private(set) var window: NSWindow?
    private let store: ClipboardStore
    private var keyMonitor: Any?
    private var additionalInputWindow: NSWindow?
    private var closeAfterExport = false
    private var documentChanges: AnyCancellable?
    var cancelGesture: (() -> Bool)?

    init(image: ImagePayload, store: ClipboardStore) {
        self.store = store
        super.init()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1040, height: 760)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: min(1040, screen.width), height: min(760, screen.height)), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Editar imagem · Bolso"
        window.minSize = NSSize(width: 680, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ImageEditorView(session: self))
        self.window = window
        window.center()
        restorePreferences()
        installKeyboardMonitor()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let decoded = image.decode()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.busy = false
                if let decoded { self.document = ImageEditorDocument(image: decoded); self.message = "Clique e arraste para marcar a imagem." }
                else { self.message = "Não foi possível abrir esta imagem. Feche e tente novamente." }
            }
        }
    }
    init(document: ImageEditorDocument, toolbar: NSWindow, canvasWindow: NSWindow, store: ClipboardStore) {
        self.store = store
        self.document = document
        super.init()
        self.window = toolbar
        self.additionalInputWindow = canvasWindow
        self.closeAfterExport = true
        self.busy = false
        self.message = "Ajuste a área ou comece a marcar."
        toolbar.delegate = self
        documentChanges = document.objectWillChange.sink { [weak self] _ in self?.confirmingDiscard = false }
        restorePreferences()
        installKeyboardMonitor()
    }
    private func restorePreferences() {
        let defaults = Self.preferences
        if let raw = defaults.string(forKey: "editor.tool"), let tool = AnnotationTool(rawValue: raw) { self.tool = tool }
        if let name = defaults.string(forKey: "editor.color"), let saved = Self.color(named: name) { color = saved }
        if let width = defaults.object(forKey: "editor.width") as? Double { self.width = min(16, max(2, width)) }
        if let size = defaults.object(forKey: "editor.fontSize") as? Double { fontSize = min(96, max(12, size)) }
        textBackground = defaults.bool(forKey: "editor.textBackground")
    }
    /// A palette name, or #RRGGBB for a color picked in the color panel.
    static func name(of color: NSColor) -> String? {
        if let entry = palette.first(where: { $0.1 == color }) { return entry.0 }
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }
    static func color(named name: String) -> NSColor? {
        if let entry = palette.first(where: { $0.0 == name }) { return entry.1 }
        guard name.count == 7, name.hasPrefix("#"), let value = Int(name.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
    private func installKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window || event.window === self.additionalInputWindow else { return event }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "w" {
                self.window?.performClose(nil); return nil
            }
            // Preserve the native field editor's undo, copy, paste and selection behavior.
            if let field = event.window?.firstResponder as? NSTextView, field.isFieldEditor {
                if event.keyCode == 53 { event.window?.makeFirstResponder(nil); return nil }
                if event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() {
                    let action: Selector?
                    switch key {
                    case "a": action = #selector(NSText.selectAll(_:))
                    case "c": action = #selector(NSText.copy(_:))
                    case "v": action = #selector(NSText.paste(_:))
                    case "x": action = #selector(NSText.cut(_:))
                    default: action = nil
                    }
                    if let action { NSApp.sendAction(action, to: field, from: nil); return nil }
                    if key == "z" {
                        if event.modifierFlags.contains(.shift) { field.undoManager?.redo() } else { field.undoManager?.undo() }
                        return nil
                    }
                }
                return event
            }
            if event.keyCode == 53 {
                if self.cancelGesture?() != true { self.window?.performClose(nil) }
                return nil
            }
            if !self.busy, event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() {
                switch key {
                case "z": if event.modifierFlags.contains(.shift) { self.document?.redo() } else { self.document?.undo() }
                case "c": if event.modifierFlags.contains(.shift) { self.copyText() } else { self.copyImage() }
                case "s": self.saveImage()
                default: return event
                }
                return nil
            }
            return event
        }
    }
    func show() { NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }
    func canClose() -> Bool {
        // The first read may wait minutes while macOS prepares OCR, so it never blocks closing.
        guard !busy || recognizing else { NSSound.beep(); return false }
        guard document?.isDirty == true else { return true }
        // runModal drops any alert to the modal panel level, under the frozen screen, where nobody
        // can answer it and the whole Mac seems locked. Captures ask in the toolbar instead.
        if closeAfterExport {
            if confirmingDiscard { return true }
            confirmingDiscard = true
            return false
        }
        return Alerts.discardEdits().runModal() == .alertSecondButtonReturn
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { canClose() }
    func windowDidResignKey(_ notification: Notification) { _ = cancelGesture?() }
    func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        window?.contentView = nil; window?.delegate = nil; window = nil
        document = nil; cancelGesture = nil; additionalInputWindow = nil; documentChanges = nil
        onClose?(); onClose = nil
    }
    func copyImage() { export(to: nil) }
    /// Reads the flattened result, so pixelated areas stay unreadable.
    func copyText() {
        guard !busy, let document else { return }
        _ = cancelGesture?()
        busy = true; recognizing = true
        message = TextRecognizer.isPrepared ? "Lendo o texto…" : "Preparando o reconhecimento de texto; na primeira vez pode levar até um minuto…"
        let image = document.image, annotations = document.annotations
        TextRecognizer.recognize({ ImageAnnotationRenderer.render(image: image, annotations: annotations) }) { [weak self] text in
            guard let self, self.window != nil else { return }
            self.busy = false; self.recognizing = false
            guard let text, let clip = Clip.plainText(text) else { self.message = "Nenhum texto encontrado nesta imagem."; return }
            guard self.store.write(clip, plain: false) else { self.message = "Não foi possível copiar o texto. Tente novamente."; return }
            self.message = "Texto copiado. Use ⌘V para colar."
            // Unsaved marks keep the capture open instead of asking to discard them.
            if self.closeAfterExport, document.isDirty == false { self.window?.performClose(nil) }
        }
    }
    func beginDrag() -> URL? {
        guard !busy, let document else { return nil }
        _ = cancelGesture?()
        guard let png = ImageAnnotationRenderer.png(image: document.image, annotations: document.annotations),
              let url = DragFiles.write(png, name: closeAfterExport ? "Bolso-print.png" : "Bolso-editado.png") else {
            message = "Não foi possível preparar a imagem para arrastar."; return nil
        }
        // The frozen screen would cover every drop target, so the capture steps aside while dragging.
        if closeAfterExport { for window in [window, additionalInputWindow].compactMap({ $0 }) { window.alphaValue = 0; window.ignoresMouseEvents = true } }
        return url
    }
    func endDrag(file: URL, delivered: Bool) {
        DragFiles.discard(file, after: delivered ? 120 : 0)
        if closeAfterExport { for window in [window, additionalInputWindow].compactMap({ $0 }) { window.alphaValue = 1; window.ignoresMouseEvents = false } }
        guard delivered, let document else { return }
        document.markDelivered()
        message = "Imagem entregue ao outro app."
        if closeAfterExport { window?.performClose(nil) }
    }
    func saveImage() {
        guard !busy, let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = closeAfterExport ? "Bolso-print.png" : "Bolso-editado.png"
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .OK, let url = panel.url { self?.export(to: url) }
        }
        // A sheet would hang off the small capture toolbar; a free panel must float above the frozen screen.
        if closeAfterExport {
            panel.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
            panel.begin(completionHandler: completion)
        } else {
            panel.beginSheetModal(for: window, completionHandler: completion)
        }
    }
    private func export(to url: URL?) {
        guard !busy, let document else { return }
        _ = cancelGesture?()
        busy = true; message = "Preparando imagem…"
        let image = document.image, annotations = document.annotations
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<Clip?, Error> = autoreleasepool {
                do {
                    guard let png = ImageAnnotationRenderer.png(image: image, annotations: annotations) else { throw EditorError.render }
                    if let url { try png.write(to: url, options: .atomic); return .success(nil) }
                    guard let clip = Clip.renderedImage(png) else { throw EditorError.tooLarge }
                    return .success(clip)
                } catch { return .failure(error) }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.busy = false
                switch result {
                case .success(let clip):
                    if let clip, !self.store.write(clip, plain: false) { self.message = "Não foi possível copiar. Tente novamente."; return }
                    document.markDelivered()
                    self.message = url == nil ? "Imagem copiada. Use ⌘V para colar." : "Cópia PNG salva."
                    if self.closeAfterExport { self.window?.performClose(nil) }
                case .failure(let error): self.message = error.localizedDescription
                }
            }
        }
    }
    deinit { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }
}
private enum EditorError: LocalizedError {
    case render, tooLarge
    var errorDescription: String? {
        switch self {
        case .render: return "Não foi possível gerar a imagem. Tente novamente."
        case .tooLarge: return "O PNG excede o limite de memória para copiar. Use Salvar cópia…"
        }
    }
}
