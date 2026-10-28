import AppKit
import SwiftUI
import BolsoCore

/// Freezes every display, lets the user drag a region on one of them and annotates it in place.
final class ScreenCaptureSession: NSObject {
    /// Runs after the screens are frozen and before the overlays take focus.
    var onCaptured: (() -> Void)?
    var onClose: (() -> Void)?
    var onError: ((String) -> Void)?
    private(set) var overlays: [CaptureOverlayWindow] = []
    private(set) var editor: ImageEditorSession?
    private let store: ClipboardStore
    private var keyMonitor: Any?
    private var task: Task<Void, Never>?
    private var toolbarSize = CGSize.zero
    private static let requestedKey = "requestedScreenCapture"

    init(store: ClipboardStore) { self.store = store }

    /// macOS shows its own prompt only on the first request; later denials need Bolso's guidance.
    static func ensurePermission() -> (granted: Bool, prompted: Bool) {
        if CGPreflightScreenCaptureAccess() { return (true, false) }
        let prompted = !UserDefaults.standard.bool(forKey: requestedKey)
        UserDefaults.standard.set(true, forKey: requestedKey)
        return (CGRequestScreenCaptureAccess(), prompted)
    }

    func start() {
        let displays = CaptureDisplay.connected()
        let windows = CaptureWindows.onScreen(), primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        task = Task { @MainActor [weak self] in
            let result: Result<[CapturedDisplay], Error>
            do {
                var snapshots = try await ScreenCaptureProvider.capture(displays)
                for index in snapshots.indices { snapshots[index].windows = CaptureWindows.local(windows, on: snapshots[index].display, primaryHeight: primaryHeight) }
                result = .success(snapshots)
            } catch { result = .failure(error) }
            // Only finish() cancels, and it has already torn the session down.
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let snapshots): self.present(snapshots)
            case .failure(let error):
                let onError = self.onError
                self.finish()
                onError?(((error as? ScreenCaptureFailure) ?? .unavailable).localizedDescription)
            }
        }
    }

    func present(_ snapshots: [CapturedDisplay]) {
        onCaptured?(); onCaptured = nil
        for snapshot in snapshots {
            let window = CaptureOverlayWindow(contentRect: snapshot.display.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isReleasedWhenClosed = false
            window.hasShadow = false
            window.animationBehavior = .none
            let view = CaptureSelectionView(snapshot: snapshot)
            view.onSelect = { [weak self, weak view] rect in
                guard let self, let view else { return }
                self.select(rect, on: view)
            }
            window.contentView = view
            window.setFrame(snapshot.display.frame, display: false)
            overlays.append(window)
            window.orderFrontRegardless()
            view.updateHover(at: view.convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.editor == nil, self.overlays.contains(where: { $0 === event.window }) else { return event }
            if event.keyCode == 53 { self.finish(); return nil }
            return event
        }
        show()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let editor { editor.window?.orderFrontRegardless(); editor.window?.makeKey(); return }
        let cursor = NSEvent.mouseLocation
        (overlays.first { $0.frame.contains(cursor) } ?? overlays.first)?.makeKeyAndOrderFront(nil)
    }

    private func select(_ rect: CGRect, on view: CaptureSelectionView) {
        guard let overlay = view.window as? CaptureOverlayWindow else { return }
        let snapshot = view.snapshot, display = snapshot.display
        let imageSize = CGSize(width: snapshot.image.width, height: snapshot.image.height)
        guard let pixels = CaptureGeometry.pixelRect(for: rect, displaySize: display.frame.size, imageSize: imageSize),
              let cropped = snapshot.image.cropping(to: pixels) else {
            if editor != nil { view.showSelection(view.canvas?.frame) }
            return
        }
        let selection = CaptureGeometry.displayRect(for: pixels, displaySize: display.frame.size, imageSize: imageSize)
        if let editor {
            guard editor.document?.replaceImage(cropped) == true else { view.showSelection(view.canvas?.frame); return }
            view.showSelection(selection)
            if let toolbar = editor.window { place(toolbar, around: selection, on: display) }
            return
        }
        // The other displays return to normal use while this region is annotated.
        for window in overlays where window !== overlay { window.orderOut(nil); window.contentView = nil }
        overlays = [overlay]
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }

        let document = ImageEditorDocument(image: cropped)
        let toolbar = CaptureToolbarPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        toolbar.level = NSWindow.Level(rawValue: overlay.level.rawValue + 1)
        toolbar.collectionBehavior = overlay.collectionBehavior
        toolbar.isReleasedWhenClosed = false
        toolbar.isOpaque = false
        toolbar.backgroundColor = .clear
        toolbar.hasShadow = true
        toolbar.becomesKeyOnlyIfNeeded = true
        toolbar.isMovableByWindowBackground = true
        let editor = ImageEditorSession(document: document, toolbar: toolbar, canvasWindow: overlay, store: store)
        let content = NSHostingController(rootView: CaptureToolbarView(editor: editor, document: document))
        content.sizingOptions = []
        let width = min(720, display.visibleFrame.width)
        toolbarSize = CGSize(width: width, height: content.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        toolbar.contentViewController = content
        place(toolbar, around: selection, on: display)
        editor.onClose = { [weak self] in self?.finish() }
        self.editor = editor
        view.beginEditing(rect: selection, editor: editor, document: document)
        toolbar.orderFrontRegardless()
    }

    private func place(_ toolbar: NSWindow, around selection: CGRect, on display: CaptureDisplay) {
        toolbar.setFrame(CaptureGeometry.toolbarFrame(size: toolbarSize, selection: CaptureGeometry.globalRect(for: selection, screenFrame: display.frame),
                                                      visibleFrame: display.visibleFrame), display: true)
    }

    func canClose() -> Bool { editor?.canClose() ?? true }

    private func finish() {
        task?.cancel(); task = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        editor = nil
        for window in overlays { window.orderOut(nil); window.contentView = nil }
        overlays = []
        onClose?(); onClose = nil
    }
}
