import SwiftUI
import BolsoCore

struct ImageEditorView: View {
    @ObservedObject var session: ImageEditorSession
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Editar imagem").font(.headline)
                    Text("Desenhe, destaque e compartilhe.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fechar") { session.window?.performClose(nil) }
                if session.document != nil { ImageDragHandle(session: session).disabled(session.busy) }
                Button("Copiar texto") { session.copyText() }.disabled(session.busy || session.document == nil).help("Reconhecer e copiar o texto da imagem (⌘⇧C)")
                Button("Salvar cópia…") { session.saveImage() }.disabled(session.busy || session.document == nil)
                Button("Copiar imagem") { session.copyImage() }.buttonStyle(.borderedProminent).disabled(session.busy || session.document == nil)
            }.padding(18)
            Divider()
            ImageEditorTools(session: session)
            Divider()
            if let document = session.document {
                EditorDocumentView(session: session, document: document)
            } else {
                VStack { if session.busy { ProgressView() }; Text(session.message).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(minWidth: 640, minHeight: 420)
    }
}

struct ImageEditorTools: View {
    @ObservedObject var session: ImageEditorSession
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) { toolButtons(iconOnly: false); toolButtons(iconOnly: true) }
            HStack(spacing: 12) {
                ForEach(ImageEditorSession.palette, id: \.0) { entry in
                    Button { session.color = entry.1 } label: {
                        Circle().fill(Color(nsColor: entry.1)).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                            .padding(3).overlay(Circle().stroke(session.color == entry.1 ? Color.accentColor : .clear, lineWidth: 2))
                    }.buttonStyle(.plain).help(entry.0).accessibilityLabel(entry.0)
                        .accessibilityAddTraits(session.color == entry.1 ? .isSelected : [])
                }.disabled(session.tool == .blur)
                Divider().frame(height: 24)
                if session.tool == .text {
                    TextField("Digite o texto e clique na imagem", text: $session.text).textFieldStyle(.roundedBorder)
                    Toggle("Fundo", isOn: $session.textBackground).toggleStyle(.checkbox).help("Texto sobre uma caixa da cor escolhida")
                    Slider(value: $session.fontSize, in: 12...96, step: 1).frame(width: 80).accessibilityLabel("Tamanho do texto")
                    Text("\(Int(session.fontSize))").monospacedDigit().frame(width: 24)
                } else {
                    Text(widthLabel).font(.caption)
                    Slider(value: $session.width, in: 2...16, step: 1).frame(width: 110).accessibilityLabel(widthLabel)
                    Text("\(Int(session.width))").monospacedDigit().frame(width: 24)
                    Spacer()
                }
            }
        }.padding(16).disabled(session.busy)
    }
    private var widthLabel: String {
        switch session.tool {
        case .counter: return "Tamanho"
        case .blur: return "Intensidade"
        default: return "Traço"
        }
    }
    private func toolButtons(iconOnly: Bool) -> some View {
        HStack {
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                Button { session.tool = tool } label: {
                    if iconOnly { Image(systemName: tool.symbol).frame(width: 22) } else { Label(tool.rawValue, systemImage: tool.symbol) }
                }
                    .tint(session.tool == tool ? .accentColor : .secondary)
                    .buttonStyle(.bordered)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(session.tool == tool ? Color.accentColor : .clear, lineWidth: 1.5))
                    .help(tool.rawValue)
                    .accessibilityLabel(tool.rawValue)
                    .accessibilityAddTraits(session.tool == tool ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}
private struct EditorDocumentView: View {
    @ObservedObject var session: ImageEditorSession
    @ObservedObject var document: ImageEditorDocument
    var body: some View {
        VStack(spacing: 0) {
            ImageEditorCanvas(session: session, document: document).padding(24)
                .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.message).font(.caption).accessibilityLabel(session.message)
                    Text("\(document.image.width) × \(document.image.height) px · Shift: círculo perfeito").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if session.busy { ProgressView().controlSize(.small) }
                Button { document.undo() } label: { Label("Desfazer", systemImage: "arrow.uturn.backward") }
                    .disabled(session.busy || document.annotations.isEmpty).help("Desfazer (⌘Z)")
                Button { document.redo() } label: { Label("Refazer", systemImage: "arrow.uturn.forward") }
                    .disabled(session.busy || document.redoStack.isEmpty).help("Refazer (⌘⇧Z)")
            }.padding(16)
        }
    }
}
