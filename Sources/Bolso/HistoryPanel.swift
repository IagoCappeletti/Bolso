import AppKit
import SwiftUI
import BolsoCore

final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PanelSession: NSObject, ObservableObject, NSWindowDelegate {
    @Published var selection = 0
    let store: ClipboardStore
    private(set) var panel: HistoryPanel?
    private var keyMonitor: Any?
    enum CloseReason { case dismiss, paste, edit, capture }
    private(set) var closeReason: CloseReason = .dismiss
    var onClose: (() -> Void)?
    var onEdit: ((Clip) -> Void)?
    var onChoose: ((Clip, Bool) -> Void)?
    init(store: ClipboardStore) { self.store = store }
    func show() {
        let panel = HistoryPanel(contentRect: NSRect(x: 0, y: 0, width: 410, height: 480), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = "Bolso"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: HistoryView(session: self, store: store))
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let x = min(max(cursor.x + 12, visible.minX), visible.maxX - panel.frame.width)
            let y = min(max(cursor.y - panel.frame.height - 12, visible.minY), visible.maxY - panel.frame.height)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        self.panel = panel
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handle(event) ? nil : event
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    func handle(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "e" {
            edit(selection); return true
        }
        switch event.keyCode {
        case 53: close(); return true
        case 125: selection = min(selection + 1, max(0, store.items.count - 1)); return true
        case 126: selection = max(0, selection - 1); return true
        case 36, 76: choose(selection, plain: event.modifierFlags.contains(.option)); return true
        default:
            if event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control),
               let number = [UInt16(18): 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9][event.keyCode] {
                choose(number - 1, plain: event.modifierFlags.contains(.option)); return true
            }
            return false
        }
    }
    func choose(_ index: Int, plain: Bool) {
        guard store.items.indices.contains(index) else { return }
        onChoose?(store.items[index], plain)
    }
    func edit(_ index: Int) {
        guard store.items.indices.contains(index), store.items[index].editableImage != nil else { return }
        onEdit?(store.items[index])
    }
    func dragFiles(for clip: Clip) -> [URL] {
        if case .files(let urls) = clip.payload { return urls }
        guard let image = clip.editableImage else { return [] }
        let png = image.type == .png ? image.original
            : image.decode().flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
        guard let png, let url = DragFiles.write(png, name: "Bolso-imagem.png") else { return [] }
        return [url]
    }
    func endDrag(_ files: [URL], delivered: Bool) {
        // Only the temporary copies go away; copied files stay where they are.
        for file in files where file.path.hasPrefix(DragFiles.root.path) { DragFiles.discard(file, after: delivered ? 120 : 0) }
        if delivered { close() }
    }
    func close(reason: CloseReason = .dismiss) {
        guard let panel else { return }
        closeReason = reason
        self.panel = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        panel.delegate = nil
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
        onClose?()
    }
    func windowDidResignKey(_ notification: Notification) { close() }
    deinit { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }
}

private struct HistoryView: View {
    @ObservedObject var session: PanelSession
    @ObservedObject var store: ClipboardStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bolso").font(.system(size: 17, weight: .semibold))
                    Text(store.paused ? "Captura pausada" : "Seu histórico, à mão")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("⌘ ⇧ V").font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary).padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                Button { session.close() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary).frame(width: 24, height: 24)
                }.buttonStyle(.plain).help("Fechar (Esc)").accessibilityLabel("Fechar histórico")
            }.padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 16)

            HStack {
                Text("RECENTES").font(.system(size: 10, weight: .semibold)).tracking(1)
                Spacer()
                Text("\(store.items.count) de 25").font(.system(size: 10, design: .monospaced))
            }.foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 8)

            if store.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
                    Text("Seu bolso está vazio").font(.system(size: 14, weight: .medium))
                    Text("Copie um texto, imagem ou arquivo para começar.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                                ClipRow(item: item, index: index, selected: index == session.selection,
                                        paste: { session.choose(index, plain: NSEvent.modifierFlags.contains(.option)) },
                                        edit: { session.edit(index) },
                                        prepareDrag: { session.dragFiles(for: item) },
                                        finishDrag: { session.endDrag($0, delivered: $1) }).id(index)
                            }
                        }.padding(.horizontal, 10).padding(.bottom, 10)
                    }.onChange(of: session.selection) { proxy.scrollTo($0) }
                }
            }
            Divider().opacity(0.5)
            HStack(spacing: 12) {
                hint("↑↓", "navegar")
                hint("↵", "colar")
                hint("⌘1–9", "direto")
                Spacer(minLength: 0)
                hint("⌥", "texto puro")
            }.padding(.horizontal, 18).padding(.vertical, 13)
        }.frame(width: 410, height: 480)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.1), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onChange(of: store.items.map(\.id)) { _ in session.selection = 0 }
    }
    private func hint(_ key: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.system(size: 10, weight: .medium, design: .monospaced))
            Text(title).font(.system(size: 10))
        }.foregroundStyle(.secondary)
    }
}

private struct ClipRow: View {
    let item: Clip
    let index: Int
    let selected: Bool
    let paste: () -> Void
    let edit: () -> Void
    let prepareDrag: () -> [URL]
    let finishDrag: ([URL], Bool) -> Void
    private var draggable: Bool {
        if case .files = item.payload { return true }
        return item.editableImage != nil
    }
    private var label: String {
        switch item.payload {
        case .text: return "Texto"
        case .image(let image): return image.canEdit ? "Imagem · clique na foto para editar" : "Somente miniatura"
        case .files(let urls): return item.editableImage != nil ? "WebP · clique na foto para editar" : (urls.count == 1 ? "Arquivo" : "\(urls.count) arquivos")
        }
    }
    private var title: String {
        switch item.payload {
        case .image: return "Imagem copiada"
        case .files(let urls): return urls.map(\.lastPathComponent).joined(separator: ", ")
        case .text: return item.preview
        }
    }
    private var thumbnailHelp: String {
        if let image = item.imagePreview {
            return image.canEdit ? "Editar imagem (⌘E)" : "Somente miniatura: imagem acima de 32 MiB ou 24 milhões de pixels. Clique para colar."
        }
        return "Colar item"
    }
    private var symbol: String {
        switch item.payload {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .files: return "doc"
        }
    }
    var body: some View {
        HStack(spacing: 11) {
            Button(action: item.editableImage == nil ? paste : edit) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045))
                    if let png = item.imagePreview, let image = NSImage(data: png.thumbnail) {
                        Image(nsImage: image).resizable().scaledToFit().padding(3)
                    } else {
                        Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(.secondary)
                    }
                }.frame(width: 40, height: 40)
            }.buttonStyle(.plain)
                .overlay {
                    if draggable {
                        DragSourceRepresentable(prepare: prepareDrag, finish: finishDrag, click: item.editableImage == nil ? paste : edit,
                                                cursor: nil, help: thumbnailHelp + " · arraste para levar a outro app")
                    }
                }
                .help(thumbnailHelp)
                .accessibilityLabel(item.editableImage == nil ? "Colar item" : "Editar imagem")
            Button(action: paste) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if index < 9 {
                        Text("⌘\(index + 1)").font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                            .frame(width: 30, height: 22)
                            .background(Color.primary.opacity(selected ? 0.07 : 0.03), in: RoundedRectangle(cornerRadius: 5))
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help("Colar item (Enter)").accessibilityLabel("\(index + 1). Colar \(item.preview)")
            if item.editableImage != nil {
                Button(action: edit) { Image(systemName: "pencil") }
                    .buttonStyle(.plain).help("Editar imagem (⌘E)").accessibilityLabel("Editar imagem")
            }
        }.padding(.horizontal, 10).padding(.vertical, 9)
            .background(selected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor.opacity(0.22) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
    }
}
