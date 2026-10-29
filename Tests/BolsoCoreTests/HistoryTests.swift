import BolsoCore
import AppKit
import ImageIO

@main
struct Checks {
    static func main() {
        var history = History<Int>(same: ==)
        for n in 0..<30 { history.insert(n) }
        precondition(history.items == Array((5..<30).reversed()))
        history.insert(10)
        precondition(history.items.first == 10)
        precondition(history.items.count == 25)
        precondition(history.items.filter { $0 == 10 }.count == 1)
        history.clear()
        precondition(history.items.isEmpty)
        print("PASS: capacidade, ordem, deduplicação e limpeza")
        clipboardChecks()
        summaryChecks()
        editorChecks()
        webPChecks()
        captureGeometryChecks()
        toolChecks()
    }
    static func clipboardChecks() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Olá Bolso", forType: .string)
        let first = Clip.read(from: board)!
        precondition(Clip.read(from: board)!.fingerprint == first.fingerprint)
        board.setData(Data(), forType: Clip.concealed)
        precondition(Clip.read(from: board) == nil)
        board.clearContents()
        let normal = NSPasteboardItem()
        normal.setString("normal", forType: .string)
        let secret = NSPasteboardItem()
        secret.setString("secret", forType: .string)
        secret.setData(Data(), forType: Clip.concealed)
        board.writeObjects([normal, secret])
        precondition(Clip.read(from: board) == nil)
        board.clearContents()
        board.setString(String(repeating: "x", count: Clip.textLimit + 1), forType: .string)
        precondition(Clip.read(from: board) == nil)
        let rich = NSAttributedString(string: "Texto rico", attributes: [.font: NSFont.boldSystemFont(ofSize: 20)])
        let rtf = try! rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        board.clearContents()
        board.setString(rich.string, forType: .string)
        board.setData(rtf, forType: .rtf)
        let richClip = Clip.read(from: board)!
        precondition(richClip.write(to: board, plain: false))
        precondition(board.data(forType: .rtf) == rtf)
        precondition(richClip.write(to: board, plain: true))
        precondition(board.string(forType: .string) == rich.string)
        precondition(board.data(forType: .rtf) == nil)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 800, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        memset(bitmap.bitmapData!, 127, bitmap.bytesPerRow * bitmap.pixelsHigh)
        let png = bitmap.representation(using: .png, properties: [:])!
        board.clearContents()
        board.setData(png, forType: .png)
        let picture = Clip.read(from: board)!
        guard case .image(let thumbnail) = picture.payload else { fatalError("Expected image") }
        let source = CGImageSourceCreateWithData(thumbnail.thumbnail as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        precondition(image.width == 256 && image.height == 128)
        precondition(!picture.write(to: board, plain: true))
        precondition(picture.write(to: board, plain: false))
        precondition(board.data(forType: .png) == png)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("bolso-check-\(UUID()).txt")
        try! Data("test".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        board.clearContents()
        board.writeObjects([file as NSURL])
        let files = Clip.read(from: board)!
        guard case .files(let urls) = files.payload else { fatalError("Expected files") }
        precondition(urls == [file])
        precondition(files.write(to: board, plain: false))
        precondition(files.write(to: board, plain: true))
        precondition(board.string(forType: .string) == file.path)
        try! FileManager.default.removeItem(at: file)
        precondition(!files.write(to: board, plain: false))
        print("PASS: ConcealedType, limite de texto, RTF/texto puro, miniatura 256px e referências de arquivos")
    }
}
