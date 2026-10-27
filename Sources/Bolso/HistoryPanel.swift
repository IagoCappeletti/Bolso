import AppKit
import SwiftUI
import BolsoCore

final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PanelSession: NSObject, ObservableObject, NSWindowDelegate {
    @Published var selection = 0
    @Published var query = "" { didSet { selection = 0 } }
    var filtered: [Clip] { store.items.filter { $0.matches(query) } }
    let store: ClipboardStore
    private(set) var panel: HistoryPanel?
    private var keyMonitor: Any?
    var onClose: (() -> Void)?
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
        switch event.keyCode {
        case 53: close(); return true
        case 125: selection = min(selection + 1, max(0, filtered.count - 1)); return true
        case 126: selection = max(0, selection - 1); return true
        case 36, 76: choose(selection, plain: event.modifierFlags.contains(.option)); return true
        default:
            if !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control),
               let number = [UInt16(18): 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9][event.keyCode] {
                choose(number - 1, plain: event.modifierFlags.contains(.option)); return true
            }
            return false
        }
    }
    func choose(_ index: Int, plain: Bool) {
        guard filtered.indices.contains(index) else { return }
        onChoose?(filtered[index], plain)
    }
    func close() {
        guard let panel else { return }
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
    @FocusState private var searchFocused: Bool
    private var results: [Clip] { session.filtered }

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

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar no histórico", text: $session.query)
                    .textFieldStyle(.plain).font(.system(size: 13)).focused($searchFocused)
                if !session.query.isEmpty {
                    Button { session.query = ""; searchFocused = true } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain).accessibilityLabel("Limpar busca")
                }
            }.padding(11)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(searchFocused ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1))
                .padding(.horizontal, 16)

            HStack {
                Text(session.query.isEmpty ? "RECENTES" : "RESULTADOS")
                    .font(.system(size: 10, weight: .semibold)).tracking(1)
                Spacer()
                Text("\(results.count) de 25").font(.system(size: 10, design: .monospaced))
            }.foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)

            if results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: store.items.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                        .font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
                    Text(store.items.isEmpty ? "Seu bolso está vazio" : "Nenhum item encontrado")
                        .font(.system(size: 14, weight: .medium))
                    Text(store.items.isEmpty ? "Copie um texto, imagem ou arquivo para começar." : "Tente buscar por outro trecho ou nome.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                Button { session.choose(index, plain: NSEvent.modifierFlags.contains(.option)) } label: {
                                    ClipRow(item: item, index: index, selected: index == session.selection)
                                }.buttonStyle(.plain).id(index)
                                    .accessibilityLabel("\(index + 1). \(item.preview)")
                            }
                        }.padding(.horizontal, 10).padding(.bottom, 10)
                    }.onChange(of: session.selection) { proxy.scrollTo($0) }
                        .onChange(of: session.query) { _ in proxy.scrollTo(0, anchor: .top) }
                }
            }
            Divider().opacity(0.5)
            HStack(spacing: 12) {
                hint("↑↓", "navegar")
                hint("↵", "colar")
                hint("1–9", "direto")
                Spacer(minLength: 0)
                hint("⌥", "texto puro")
            }.padding(.horizontal, 18).padding(.vertical, 13)
        }.frame(width: 410, height: 480)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.1), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onAppear { searchFocused = true }
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
    private var label: String {
        switch item.payload {
        case .text: return "Texto"
        case .image: return "Imagem · miniatura"
        case .files(let urls): return urls.count == 1 ? "Arquivo" : "\(urls.count) arquivos"
        }
    }
    private var title: String {
        switch item.payload {
        case .image: return "Imagem copiada"
        case .files(let urls): return urls.map(\.lastPathComponent).joined(separator: ", ")
        case .text: return item.preview
        }
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
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045))
                if case .image(let png) = item.payload, let image = NSImage(data: png) {
                    Image(nsImage: image).resizable().scaledToFit().padding(3)
                } else {
                    Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(.secondary)
                }
            }.frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if index < 9 {
                Text("\(index + 1)").font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(selected ? 0.07 : 0.03), in: RoundedRectangle(cornerRadius: 5))
            }
        }.padding(.horizontal, 10).padding(.vertical, 9)
            .background(selected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor.opacity(0.22) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
    }
}
