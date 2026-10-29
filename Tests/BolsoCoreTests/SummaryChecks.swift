import AppKit
import BolsoCore

func summaryChecks() {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    func clip(_ write: (NSPasteboard) -> Void) -> Clip {
        board.clearContents(); write(board)
        return Clip.read(from: board)!
    }
    let text = clip { $0.setString("  Proposta enviada.\n\nValor final:\tR$ 182.900,00  ", forType: .string) }
    precondition(text.kind == .text && text.title == "Proposta enviada. Valor final: R$ 182.900,00" && text.kindLabel == "Texto", "Text titles fold whitespace into one line")
    let link = clip { $0.setString("https://www.github.com/IagoCappeletti/Bolso/releases/latest/?tab=1", forType: .string) }
    precondition(link.kind == .link && link.title == "github.com/IagoCappeletti/Bolso/releases/latest" && link.kindLabel == "Link", "Links show host and path")
    precondition(clip { $0.setString("veja https://github.com e responda", forType: .string) }.kind == .text, "A sentence with a link stays text")
    let pdf = clip { $0.writeObjects([URL(fileURLWithPath: "/tmp/Edital 12-2026.pdf") as NSURL]) }
    precondition(pdf.kind == .files && pdf.title == "Edital 12-2026.pdf" && pdf.kindLabel == "PDF", "Files show their name and extension")
    let many = clip { $0.writeObjects(["a.png", "b.png", "c.txt"].map { URL(fileURLWithPath: "/tmp/" + $0) as NSURL }) }
    precondition(many.title == "a.png e mais 2" && many.kindLabel == "3 arquivos")
    precondition(clip { $0.writeObjects([URL(fileURLWithPath: "/tmp/Licitações", isDirectory: true) as NSURL]) }.kindLabel == "Pasta")
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1440, pixelsHigh: 1040, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let image = clip { $0.setData(bitmap.representation(using: .png, properties: [:])!, forType: .png) }
    precondition(image.kind == .image && image.title == "Imagem" && image.kindLabel == "1.440 × 1.040 px", "Images show their size")
    let copied = text.copiedAt
    precondition(text.age(at: copied.addingTimeInterval(30)) == "agora")
    precondition(text.age(at: copied.addingTimeInterval(125)) == "há 2 min")
    precondition(text.age(at: copied.addingTimeInterval(3 * 3600 + 5)) == "há 3 h")
    precondition(text.age(at: copied.addingTimeInterval(25 * 3600)) == "ontem")
    precondition(text.age(at: copied.addingTimeInterval(49 * 3600)) == "há 2 dias")
    print("PASS: tipo, título, descrição e idade dos itens do histórico")
}
