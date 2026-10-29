import SwiftUI
import BolsoCore

struct ImageEditorView: View {
    @ObservedObject var session: ImageEditorSession
    var body: some View {
        VStack(spacing: 0) {
            MarkupToolbar(session: session, document: session.document, closeTitle: "Fechar", saveTitle: "Salvar cópia…", copyTitle: "Copiar imagem")
            Divider()
            if let document = session.document {
                EditorDocumentView(session: session, document: document)
            } else {
                VStack(spacing: 8) { if session.busy { ProgressView() }; Text(session.message).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(minWidth: 680, minHeight: 420)
    }
}

private struct EditorDocumentView: View {
    @ObservedObject var session: ImageEditorSession
    @ObservedObject var document: ImageEditorDocument
    var body: some View {
        ImageEditorCanvas(session: session, document: document).padding(24)
            .background(Color(nsColor: .underPageBackgroundColor))
            .overlay(alignment: .bottomTrailing) {
                Text("Shift desenha círculos e caixas perfeitos").font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(.thinMaterial, in: Capsule()).padding(10)
            }
    }
}
