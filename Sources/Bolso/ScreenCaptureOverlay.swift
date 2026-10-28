import AppKit
import Combine
import SwiftUI
import BolsoCore

final class CaptureOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    // The frozen screen must also cover the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class CaptureToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    // Borderless windows have no close button, so the default performClose would only beep.
    override func performClose(_ sender: Any?) {
        if delegate?.windowShouldClose?(self) ?? true { close() }
    }
}

final class CaptureSelectionView: NSView {
    let snapshot: CapturedDisplay
    var onSelect: ((CGRect) -> Void)?
    private enum Drag { case select(from: CGPoint), resize(CGRect, CaptureEdges), move(CGRect, from: CGPoint) }
    private var drag: Drag?
    private var selection: CGRect?
    private var hovered: CGRect?
    private(set) var canvas: AnnotationCanvasView?
    private weak var document: ImageEditorDocument?
    private let handles = CaptureHandlesView()
    private var changes: AnyCancellable?
    private var tracking: NSTrackingArea?
    private var isEditing = false
    /// The region stays adjustable until the first mark, since marks are anchored to its pixels.
    var canAdjust: Bool { isEditing && document?.annotations.isEmpty == true }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(snapshot: CapturedDisplay) {
        self.snapshot = snapshot
        super.init(frame: CGRect(origin: .zero, size: snapshot.display.frame.size))
        setAccessibilityLabel("Selecione uma área da tela arrastando ou clique numa janela. Escape cancela.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        c.saveGState()
        c.translateBy(x: 0, y: bounds.height); c.scaleBy(x: 1, y: -1)
        c.draw(snapshot.image, in: bounds)
        c.restoreGState()
        let hole = selection ?? (isEditing ? nil : hovered)
        let shade = NSBezierPath(rect: bounds)
        if let hole { shade.appendRect(hole) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.48).setFill(); shade.fill()
        if let selection {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5)); border.lineWidth = 1; border.stroke()
        } else if let hovered, !isEditing {
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill(); NSBezierPath(rect: hovered).fill()
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: hovered.insetBy(dx: 1, dy: 1)); border.lineWidth = 2; border.stroke()
        }
        if !isEditing {
            let hint = selection.map { "\(Int($0.width)) × \(Int($0.height)) pt · solte para editar · Esc cancela" }
                ?? (hovered == nil ? "Arraste para selecionar a área do print · Esc cancela"
                                   : "Clique para capturar a janela · arraste para escolher uma área · Esc cancela")
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white]
            let size = (hint as NSString).size(withAttributes: attributes)
            let box = CGRect(x: max(12, (bounds.width - size.width - 28) / 2), y: 40, width: size.width + 28, height: size.height + 20)
            NSColor.black.withAlphaComponent(0.8).setFill()
            NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
            (hint as NSString).draw(at: CGPoint(x: box.minX + 14, y: box.minY + 10), withAttributes: attributes)
        }
    }

    // Handles straddle the border and the move grip sits inside it, so both must win over the canvas.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if canAdjust, let selection, let superview {
            let local = convert(point, from: superview)
            if CaptureGeometry.moveGrip(for: selection, in: bounds).contains(local) || !CaptureGeometry.edges(at: local, of: selection).isEmpty { return self }
        }
        return super.hitTest(point)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseMoved(with event: NSEvent) { updateHover(at: convert(event.locationInWindow, from: nil)) }
    func updateHover(at point: CGPoint) {
        guard !isEditing, drag == nil, selection == nil else { return }
        let window = snapshot.windows.first { $0.contains(point) }
        if window != hovered { hovered = window; needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isEditing {
            // Inside the region the canvas takes the click; here it is a handle or the outside.
            guard canAdjust, let selection else { return }
            let edges = CaptureGeometry.edges(at: point, of: selection)
            if CaptureGeometry.moveGrip(for: selection, in: bounds).contains(point) { drag = .move(selection, from: point) }
            else { drag = edges.isEmpty ? .select(from: point) : .resize(selection, edges) }
        } else {
            window?.makeKeyAndOrderFront(nil)
            drag = .select(from: point)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        selection = rect(for: drag, at: convert(event.locationInWindow, from: nil))
        // While adjusting, the hole in the shade shows the frozen screen itself.
        canvas?.isHidden = true
        handles.rect = canAdjust ? selection : nil
        if case .move = drag { NSCursor.closedHand.set() }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let drag else { return }
        self.drag = nil
        let point = convert(event.locationInWindow, from: nil)
        var rect = self.rect(for: drag, at: point)
        // A click without dragging picks the window under the pointer.
        if case .select = drag, !isEditing, rect.width < 2 || rect.height < 2, let window = snapshot.windows.first(where: { $0.contains(point) }) {
            rect = window
        }
        guard rect.width >= 2, rect.height >= 2 else {
            if isEditing { showSelection(canvas?.frame) } else { selection = nil; needsDisplay = true }
            return
        }
        selection = rect; hovered = nil; needsDisplay = true
        onSelect?(rect)
    }
    private func rect(for drag: Drag, at point: CGPoint) -> CGRect {
        switch drag {
        case .select(let start): return CaptureGeometry.selection(from: start, to: point, in: bounds)
        case .resize(let original, let edges): return CaptureGeometry.resize(original, edges: edges, to: point, in: bounds)
        case .move(let original, let start): return CaptureGeometry.move(original, from: start, to: point, in: bounds)
        }
    }

    func beginEditing(rect: CGRect, editor: ImageEditorSession, document: ImageEditorDocument) {
        isEditing = true; drag = nil; hovered = nil
        self.document = document
        let canvas = AnnotationCanvasView(frame: rect)
        canvas.session = editor; canvas.document = document
        canvas.acceptsFirstClick = true
        canvas.setAccessibilityLabel("Print selecionado. Arraste para desenhar ou use a barra de ferramentas.")
        addSubview(canvas)
        self.canvas = canvas
        handles.frame = bounds; handles.autoresizingMask = [.width, .height]
        addSubview(handles)
        editor.cancelGesture = { [weak canvas] in canvas?.cancelGesture() ?? false }
        changes = document.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.canvas?.needsDisplay = true; self?.showSelection(self?.selection) }
        }
        showSelection(rect)
        window?.makeFirstResponder(canvas)
    }
    /// Places the canvas on the region the session cropped, or restores it after an abandoned adjustment.
    func showSelection(_ rect: CGRect?) {
        selection = rect
        if let rect, let canvas { canvas.frame = rect; canvas.isHidden = false; canvas.needsDisplay = true }
        handles.rect = canAdjust ? rect : nil
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }
    override func resetCursorRects() {
        if !isEditing { addCursorRect(bounds, cursor: .crosshair) }
    }
}

/// Sits above the canvas without taking its clicks, so these cursors win over the canvas's crosshair.
private final class CaptureHandlesView: NSView {
    var rect: CGRect? { didSet { needsDisplay = true; window?.invalidateCursorRects(for: self) } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func resetCursorRects() {
        guard let s = rect else { return }
        addCursorRect(CGRect(x: s.minX - 6, y: s.minY + 6, width: 12, height: max(0, s.height - 12)), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: s.maxX - 6, y: s.minY + 6, width: 12, height: max(0, s.height - 12)), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: s.minX + 6, y: s.minY - 6, width: max(0, s.width - 12), height: 12), cursor: .resizeUpDown)
        addCursorRect(CGRect(x: s.minX + 6, y: s.maxY - 6, width: max(0, s.width - 12), height: 12), cursor: .resizeUpDown)
        addCursorRect(CaptureGeometry.moveGrip(for: s, in: bounds), cursor: .openHand)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let r = rect else { return }
        let grip = CaptureGeometry.moveGrip(for: r, in: bounds)
        let pill = NSBezierPath(roundedRect: grip, xRadius: grip.height / 2, yRadius: grip.height / 2)
        NSColor.white.setFill(); pill.fill()
        NSColor.controlAccentColor.setStroke(); pill.lineWidth = 1.5; pill.stroke()
        let symbol = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold).applying(.init(paletteColors: [.controlAccentColor]))
        if let icon = NSImage(systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right", accessibilityDescription: "Mover")?.withSymbolConfiguration(symbol) {
            icon.draw(in: CGRect(x: grip.midX - icon.size.width / 2, y: grip.midY - icon.size.height / 2, width: icon.size.width, height: icon.size.height),
                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        for point in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.midY),
                      CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)] {
            let handle = NSBezierPath(roundedRect: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8), xRadius: 2, yRadius: 2)
            NSColor.white.setFill(); handle.fill()
            NSColor.controlAccentColor.setStroke(); handle.lineWidth = 1.5; handle.stroke()
        }
    }
}

struct CaptureToolbarView: View {
    @ObservedObject var editor: ImageEditorSession
    @ObservedObject var document: ImageEditorDocument
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Print · Bolso").font(.headline)
                Text("\(document.image.width) × \(document.image.height) px").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancelar") { editor.window?.performClose(nil) }.disabled(editor.busy && !editor.recognizing).help("Cancelar (Esc)")
                ImageDragHandle(session: editor).disabled(editor.busy)
                Button("Copiar texto") { editor.copyText() }.disabled(editor.busy).help("Reconhecer e copiar o texto (⌘⇧C)")
                Button("Salvar…") { editor.saveImage() }.disabled(editor.busy).help("Salvar PNG (⌘S)")
                Button("Copiar") { editor.copyImage() }.buttonStyle(.borderedProminent).disabled(editor.busy).help("Copiar (⌘C)")
            }.padding(.horizontal, 16).padding(.top, 12)
            ImageEditorTools(session: editor)
            HStack {
                if editor.confirmingDiscard {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text("Descartar as marcações? Esc de novo também descarta.").font(.caption).lineLimit(2)
                    Spacer()
                    Button("Continuar editando") { editor.confirmingDiscard = false }.controlSize(.small)
                    Button("Descartar", role: .destructive) { editor.window?.performClose(nil) }.controlSize(.small)
                } else {
                    if editor.busy { ProgressView().controlSize(.small) }
                    Text(editor.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                }
                Button { document.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(editor.busy || document.annotations.isEmpty).help("Desfazer (⌘Z)").accessibilityLabel("Desfazer")
                Button { document.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(editor.busy || document.redoStack.isEmpty).help("Refazer (⌘⇧Z)").accessibilityLabel("Refazer")
            }.padding(.horizontal, 16).padding(.bottom, 12)
        }.background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
