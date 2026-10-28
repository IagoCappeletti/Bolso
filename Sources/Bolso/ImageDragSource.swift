import AppKit
import SwiftUI

/// Temporary PNGs handed to other apps by drag and drop; nothing else from the editor or the history touches the disk.
enum DragFiles {
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("Bolso-arrastar", isDirectory: true)
    static func write(_ png: Data, name: String) -> URL? {
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name)
            try png.write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }
    /// Receivers read the file while handling the drop; the delay covers apps that upload it a little later.
    static func discard(_ file: URL, after delay: TimeInterval) {
        let folder = file.deletingLastPathComponent()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { try? FileManager.default.removeItem(at: folder) }
    }
    static func clearAll() { try? FileManager.default.removeItem(at: root) }
}

struct ImageDragHandle: View {
    let session: ImageEditorSession
    var body: some View {
        Image(systemName: "hand.draw").font(.system(size: 15, weight: .medium))
            .frame(width: 34, height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.18)))
            .overlay(DragSourceRepresentable(prepare: { [weak session] in session?.beginDrag().map { [$0] } ?? [] },
                                             finish: { [weak session] files, delivered in
                                                 if let file = files.first { session?.endDrag(file: file, delivered: delivered) }
                                             }))
            .accessibilityLabel("Arrastar imagem para outro app")
    }
}

/// Covers a SwiftUI view with an AppKit drag source; a click without dragging still reaches `click`.
struct DragSourceRepresentable: NSViewRepresentable {
    let prepare: () -> [URL]
    let finish: ([URL], Bool) -> Void
    var click: (() -> Void)?
    var cursor: NSCursor? = .openHand
    var help = "Arraste a imagem para outro app"
    func makeNSView(context: Context) -> DragSourceView { update(DragSourceView(prepare: prepare, finish: finish)) }
    func updateNSView(_ view: DragSourceView, context: Context) { _ = update(view) }
    private func update(_ view: DragSourceView) -> DragSourceView {
        view.prepare = prepare; view.finish = finish; view.click = click; view.cursor = cursor; view.toolTip = help
        return view
    }
}

final class DragSourceView: NSView, NSDraggingSource {
    var prepare: () -> [URL]
    var finish: ([URL], Bool) -> Void
    var click: (() -> Void)?
    var cursor: NSCursor? = .openHand { didSet { window?.invalidateCursorRects(for: self) } }
    private var pressed: NSEvent?
    private var files: [URL] = []
    init(prepare: @escaping () -> [URL], finish: @escaping ([URL], Bool) -> Void) {
        self.prepare = prepare; self.finish = finish
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { if let cursor { addCursorRect(bounds, cursor: cursor) } }
    override func mouseDown(with event: NSEvent) { pressed = event }
    override func mouseUp(with event: NSEvent) {
        if pressed != nil { pressed = nil; click?() }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let pressed, hypot(event.locationInWindow.x - pressed.locationInWindow.x, event.locationInWindow.y - pressed.locationInWindow.y) > 3 else { return }
        let urls = prepare()
        guard !urls.isEmpty else { return }
        self.pressed = nil; files = urls
        let point = convert(pressed.locationInWindow, from: nil)
        let items = urls.enumerated().map { index, url -> NSDraggingItem in
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            if urls.count == 1, url.pathExtension.lowercased() == "png", let png = try? Data(contentsOf: url) { item.setData(png, forType: .png) }
            let dragging = NSDraggingItem(pasteboardWriter: item)
            let preview = NSImage(contentsOf: url) ?? NSWorkspace.shared.icon(forFile: url.path)
            let scale = min(1, 160 / max(preview.size.width, preview.size.height, 1))
            let size = NSSize(width: preview.size.width * scale, height: preview.size.height * scale)
            let offset = CGFloat(index) * 8
            dragging.setDraggingFrame(NSRect(x: point.x - size.width / 2 + offset, y: point.y - size.height / 2 - offset, width: size.width, height: size.height), contents: preview)
            return dragging
        }
        beginDraggingSession(with: items, event: pressed, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard !files.isEmpty else { return }
        let files = self.files
        self.files = []
        finish(files, operation != [])
    }
}
