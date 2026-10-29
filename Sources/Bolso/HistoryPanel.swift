import AppKit
import SwiftUI
import BolsoCore
import UniformTypeIdentifiers

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

struct HistoryView: View {
    @ObservedObject var session: PanelSession
    @ObservedObject var store: ClipboardStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 22, height: 22)
                Text("Bolso").font(.system(size: 14, weight: .semibold))
                Text(count).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button { session.close() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22).background(Color.primary.opacity(0.06), in: Circle())
                }.buttonStyle(.plain).help("Fechar (Esc)").accessibilityLabel("Fechar histórico")
            }.padding(.horizontal, 16).frame(height: 48)
            if store.paused {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                    Text("Histórico pausado: novas cópias não entram").font(.system(size: 12))
                    Spacer()
                    Button("Retomar") { store.togglePause() }.controlSize(.small)
                }.padding(.horizontal, 16).padding(.vertical, 8).background(Color.orange.opacity(0.12))
            }
            Divider().opacity(0.6)
            if store.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.system(size: 28, weight: .light)).foregroundStyle(.tertiary)
                    Text("Nada copiado ainda").font(.system(size: 14, weight: .medium))
                    Text("Copie um texto, uma imagem ou um arquivo com ⌘C e ele aparece aqui.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 260)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                                ClipRow(item: item, index: index, selected: index == session.selection,
                                        paste: { session.choose(index, plain: NSEvent.modifierFlags.contains(.option)) },
                                        edit: { session.edit(index) },
                                        prepareDrag: { session.dragFiles(for: item) },
                                        finishDrag: { session.endDrag($0, delivered: $1) }).id(index)
                            }
                        }.padding(8)
                    }.onChange(of: session.selection) { proxy.scrollTo($0) }
                }
            }
            Divider().opacity(0.6)
            HStack(spacing: 14) {
                hint("↑↓", "navegar")
                hint("↵", "colar")
                hint("⌘1–9", "direto")
                Spacer(minLength: 0)
                hint("⌥", "texto puro")
            }.padding(.horizontal, 16).frame(height: 38)
        }.frame(width: 410, height: 480)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.1), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .onChange(of: store.items.map(\.id)) { _ in session.selection = 0 }
    }
    private var count: String {
        switch store.items.count {
        case 0: return ""
        case 1: return "1 item"
        case let count: return "\(count) itens"
        }
    }
    private func hint(_ key: String, _ title: String) -> some View {
        HStack(spacing: 5) {
            Text(key).font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 17)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Text(title).font(.system(size: 11))
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
    private var thumbnailHelp: String {
        if let image = item.imagePreview {
            return image.canEdit ? "Editar imagem (⌘E)" : "Somente miniatura: imagem acima de 32 MiB ou 24 milhões de pixels. Clique para colar."
        }
        return "Colar item"
    }
    var body: some View {
        HStack(spacing: 12) {
            Button(action: item.editableImage == nil ? paste : edit) { thumbnail }
                .buttonStyle(.plain)
                .overlay {
                    if draggable {
                        DragSourceRepresentable(prepare: prepareDrag, finish: finishDrag, click: item.editableImage == nil ? paste : edit,
                                                cursor: nil, help: thumbnailHelp + " · arraste para levar a outro app")
                    }
                }
                .help(thumbnailHelp)
                .accessibilityLabel(item.editableImage == nil ? "Colar item" : "Editar imagem")
            Button(action: paste) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.system(size: 13)).lineLimit(item.kind == .text ? 2 : 1)
                        .truncationMode(item.kind == .link ? .middle : .tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(item.kindLabel) · \(item.age())").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help("Colar (Enter)").accessibilityLabel("\(index + 1). Colar \(item.preview)")
            HStack(spacing: 6) {
                if item.editableImage != nil {
                    Button(action: edit) { Image(systemName: "pencil").font(.system(size: 12)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Editar imagem (⌘E)").accessibilityLabel("Editar imagem")
                }
                Spacer(minLength: 0)
                if index < 9 {
                    Text("⌘\(index + 1)").font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(selected ? .primary : .tertiary)
                }
            }.frame(width: 50)
        }.padding(.horizontal, 10).padding(.vertical, 8)
            .background(selected ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
    }
    @ViewBuilder private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(item.kind == .link ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
            if let preview = item.imagePreview, let image = NSImage(data: preview.thumbnail) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            } else if case .files(let urls) = item.payload, let url = urls.first {
                Image(nsImage: Self.icon(for: url)).resizable().frame(width: 30, height: 30)
            } else {
                Image(systemName: item.kind == .link ? "link" : "text.alignleft").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(item.kind == .link ? Color.accentColor : .secondary)
            }
        }.frame(width: 36, height: 36)
    }
    /// Finder's icon for the type, even when the file is gone or on a disconnected volume.
    private static func icon(for url: URL) -> NSImage {
        if url.hasDirectoryPath { return NSWorkspace.shared.icon(for: .folder) }
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: url.pathExtension) ?? .data)
    }
}
