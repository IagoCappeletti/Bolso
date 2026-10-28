import AppKit
import SwiftUI
import BolsoCore

struct ImageEditorCanvas: NSViewRepresentable {
    let session: ImageEditorSession
    let document: ImageEditorDocument
    func makeNSView(context: Context) -> AnnotationCanvasView {
        let view = AnnotationCanvasView()
        view.session = session; view.document = document
        session.cancelGesture = { [weak view] in view?.cancelGesture() ?? false }
        view.setAccessibilityLabel("Imagem editável. Arraste para desenhar; use a ferramenta Texto para escrever.")
        return view
    }
    func updateNSView(_ view: AnnotationCanvasView, context: Context) {
        view.session = session; view.document = document
        view.needsDisplay = true
    }
}
final class AnnotationCanvasView: NSView {
    weak var session: ImageEditorSession?
    weak var document: ImageEditorDocument?
    private var current: Annotation?
    /// In-place captures draw on the first click, even when the toolbar holds focus.
    var acceptsFirstClick = false
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { acceptsFirstClick }
    private var imageRect: CGRect {
        guard let image = document?.image else { return .zero }
        let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width)*scale, height: CGFloat(image.height)*scale)
        return CGRect(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2, width: size.width, height: size.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let document, let c = NSGraphicsContext.current?.cgContext, imageRect.width > 0 else { return }
        let rect = imageRect
        c.saveGState(); c.clip(to: rect)
        for y in stride(from: rect.minY, to: rect.maxY, by: 12) {
            for x in stride(from: rect.minX, to: rect.maxX, by: 12) {
                let alternate = (Int((x-rect.minX)/12) + Int((y-rect.minY)/12)) % 2 == 0
                c.setFillColor(NSColor(white: alternate ? 0.92 : 0.82, alpha: 1).cgColor)
                c.fill(CGRect(x: x, y: y, width: 12, height: 12))
            }
        }
        c.translateBy(x: rect.minX, y: rect.minY)
        let scale = rect.width / CGFloat(document.image.width)
        c.scaleBy(x: scale, y: scale)
        ImageAnnotationRenderer.draw(image: document.image, annotations: document.annotations + (current.map { [$0] } ?? []), in: c)
        c.restoreGState()
    }
    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil), r = imageRect
        guard let image = document?.image, r.width > 0 else { return .zero }
        return CGPoint(x: min(CGFloat(image.width), max(0, (p.x-r.minX)*CGFloat(image.width)/r.width)),
                       y: min(CGFloat(image.height), max(0, (p.y-r.minY)*CGFloat(image.height)/r.height)))
    }
    override func mouseDown(with event: NSEvent) {
        guard let session, !session.busy, imageRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        window?.makeFirstResponder(self)
        if session.tool == .text && session.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            session.message = "Digite o texto na barra antes de clicar na imagem."; return
        }
        current = Annotation(tool: session.tool, points: [point(event)], color: session.color, width: session.width, text: session.text, fontSize: session.fontSize,
                             background: session.textBackground, number: session.tool == .counter ? document?.nextNumber ?? 1 : 0)
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard var annotation = current, let start = annotation.points.first else { return }
        var end = point(event)
        if annotation.tool == .ellipse && event.modifierFlags.contains(.shift) {
            let side = min(abs(end.x-start.x), abs(end.y-start.y))
            end = CGPoint(x: start.x + (end.x >= start.x ? side : -side), y: start.y + (end.y >= start.y ? side : -side))
        }
        switch annotation.tool {
        case .pen, .highlighter: annotation.points.append(end)
        case .text, .counter: annotation.points = [end]
        default: annotation.points = [start, end]
        }
        current = annotation; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let current else { return }
        document?.add(current); self.current = nil; needsDisplay = true
        session?.message = "Use Desfazer para corrigir ou copie/salve o resultado."
    }
    @discardableResult func cancelGesture() -> Bool {
        let hadGesture = current != nil; current = nil; needsDisplay = true; return hadGesture
    }
    override func resetCursorRects() { addCursorRect(imageRect, cursor: .crosshair) }
}
