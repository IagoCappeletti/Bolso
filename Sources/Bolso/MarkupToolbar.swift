import SwiftUI
import BolsoCore

/// The tools and actions shared by the in-place capture and the editor window.
struct MarkupToolbar: View {
    @ObservedObject var session: ImageEditorSession
    let document: ImageEditorDocument?
    let closeTitle: String
    let saveTitle: String
    let copyTitle: String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    ForEach(AnnotationTool.allCases, id: \.self) { tool in
                        Button { session.tool = tool } label: { Image(systemName: tool.symbol).font(.system(size: 13, weight: .medium)) }
                            .buttonStyle(ToolButtonStyle(selected: session.tool == tool))
                            .help(tool.rawValue).accessibilityLabel(tool.rawValue)
                            .accessibilityAddTraits(session.tool == tool ? .isSelected : [])
                    }
                }.padding(2).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                Divider().frame(height: 22)
                HStack(spacing: 6) {
                    ForEach(ImageEditorSession.palette, id: \.0) { entry in
                        Button { session.color = entry.1 } label: {
                            Circle().fill(Color(nsColor: entry.1)).frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                                .padding(3)
                                .overlay(Circle().strokeBorder(session.color == entry.1 ? Color.accentColor : .clear, lineWidth: 2))
                        }.buttonStyle(.plain).help(entry.0).accessibilityLabel(entry.0)
                            .accessibilityAddTraits(session.color == entry.1 ? .isSelected : [])
                    }
                    CustomColorButton(session: session)
                }.disabled(session.tool == .blur).opacity(session.tool == .blur ? 0.35 : 1)
                Divider().frame(height: 22)
                HStack(spacing: 6) {
                    Text(sizeLabel).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize()
                    if session.tool == .text {
                        Slider(value: Binding(get: { session.fontSize }, set: { session.fontSize = $0.rounded() }), in: 12...96).frame(width: 78).accessibilityLabel(sizeLabel)
                        Text("\(Int(session.fontSize))").font(.system(size: 11)).monospacedDigit().frame(width: 20, alignment: .leading)
                    } else {
                        Slider(value: Binding(get: { session.width }, set: { session.width = $0.rounded() }), in: 2...16).frame(width: 78).accessibilityLabel(sizeLabel)
                        Text("\(Int(session.width))").font(.system(size: 11)).monospacedDigit().frame(width: 20, alignment: .leading)
                    }
                }.controlSize(.small)
                Spacer(minLength: 0)
                if let document { HistoryButtons(session: session, document: document) }
            }.disabled(session.busy || document == nil)
            HStack(spacing: 8) {
                context.frame(maxWidth: .infinity, alignment: .leading)
                Button(closeTitle) { session.window?.performClose(nil) }
                    .buttonStyle(ActionButtonStyle()).disabled(session.busy && !session.recognizing).help("\(closeTitle) (Esc)")
                if document != nil { ImageDragHandle(session: session).disabled(session.busy) }
                Button("Copiar texto") { session.copyText() }
                    .buttonStyle(ActionButtonStyle()).disabled(session.busy || document == nil).help("Reconhecer e copiar o texto (⌘⇧C)")
                Button(saveTitle) { session.saveImage() }
                    .buttonStyle(ActionButtonStyle()).disabled(session.busy || document == nil).help("Salvar PNG (⌘S)")
                Button(copyTitle) { session.copyImage() }
                    .buttonStyle(ActionButtonStyle(prominent: true)).disabled(session.busy || document == nil).help("Copiar (⌘C)")
            }
        }.padding(12)
    }

    @ViewBuilder private var context: some View {
        if session.confirmingDiscard {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Descartar as marcações?").font(.system(size: 12, weight: .medium)).lineLimit(1)
                Button("Continuar") { session.confirmingDiscard = false }.buttonStyle(ActionButtonStyle())
                Button("Descartar") { session.window?.performClose(nil) }.buttonStyle(ActionButtonStyle(destructive: true)).help("Esc de novo também descarta")
            }
        } else if session.tool == .text {
            HStack(spacing: 8) {
                TextField("Digite e clique na imagem", text: $session.text).textFieldStyle(.roundedBorder).controlSize(.small)
                Toggle("Fundo", isOn: $session.textBackground).toggleStyle(.checkbox).controlSize(.small).help("Texto sobre uma caixa da cor escolhida")
            }
        } else {
            HStack(spacing: 6) {
                if session.busy { ProgressView().controlSize(.small) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    if let document {
                        Text("\(document.image.width) × \(document.image.height) px").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
            }.help(session.message)
        }
    }

    private var sizeLabel: String {
        switch session.tool {
        case .text: return "Tamanho"
        case .counter: return "Tamanho"
        case .blur: return "Intensidade"
        default: return "Traço"
        }
    }
}

/// A rainbow swatch that opens a small grid of colors; once one is picked, it shows that color inside the ring.
private struct CustomColorButton: View {
    @ObservedObject var session: ImageEditorSession
    private var custom: Bool { !ImageEditorSession.palette.contains { $0.1 == session.color } }
    var body: some View {
        Button { session.pickingColor.toggle() } label: {
            Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                .overlay(Circle().fill(Color(nsColor: session.color)).padding(3).opacity(custom ? 1 : 0))
                .frame(width: 16, height: 16)
                .padding(3)
                .overlay(Circle().strokeBorder(custom ? Color.accentColor : .clear, lineWidth: 2))
        }.buttonStyle(.plain).help("Mais cores").accessibilityLabel("Mais cores")
            .accessibilityAddTraits(custom ? .isSelected : [])
            .popover(isPresented: $session.pickingColor, arrowEdge: .bottom) {
                ColorGrid(selected: session.color) { session.color = $0; session.pickingColor = false }
            }
    }
}

struct ColorGrid: View {
    let selected: NSColor
    let choose: (NSColor) -> Void
    var body: some View {
        let current = ImageEditorSession.name(of: selected)
        VStack(spacing: 4) {
            ForEach(ImageEditorSession.moreColors.indices, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(ImageEditorSession.moreColors[row].indices, id: \.self) { column in
                        let color = ImageEditorSession.moreColors[row][column]
                        let name = ImageEditorSession.name(of: color)
                        Button { choose(color) } label: {
                            RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: color)).frame(width: 18, height: 18)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                                .padding(2)
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(name == current ? Color.accentColor : .clear, lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityLabel(name ?? "Cor")
                    }
                }
            }
        }.padding(10)
    }
}

private struct HistoryButtons: View {
    @ObservedObject var session: ImageEditorSession
    @ObservedObject var document: ImageEditorDocument
    var body: some View {
        HStack(spacing: 2) {
            Button { document.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(ToolButtonStyle(selected: false)).disabled(session.busy || document.annotations.isEmpty)
                .help("Desfazer (⌘Z)").accessibilityLabel("Desfazer")
            Button { document.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(ToolButtonStyle(selected: false)).disabled(session.busy || document.redoStack.isEmpty)
                .help("Refazer (⌘⇧Z)").accessibilityLabel("Refazer")
        }
    }
}

/// Square icon buttons; the selected tool keeps its fill even while the panel is not key.
struct ToolButtonStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration, selected: selected) }
    private struct Styled: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor : Color.primary.opacity(configuration.isPressed ? 0.14 : 0.001)))
                .contentShape(Rectangle())
                .opacity(enabled ? 1 : 0.35)
        }
    }
}

/// Text buttons that keep their look in a panel that never becomes key, so the main action stays recognizable.
struct ActionButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration, prominent: prominent, destructive: destructive) }
    private struct Styled: View {
        let configuration: Configuration
        let prominent: Bool
        let destructive: Bool
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: prominent ? .semibold : .regular))
                .foregroundStyle(prominent || destructive ? Color.white : Color.primary)
                .lineLimit(1)
                .padding(.horizontal, 10).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(fill.opacity(configuration.isPressed ? 0.75 : 1)))
                .opacity(enabled ? 1 : 0.4)
        }
        private var fill: Color {
            if destructive { return .red }
            return prominent ? .accentColor : Color.primary.opacity(0.09)
        }
    }
}
