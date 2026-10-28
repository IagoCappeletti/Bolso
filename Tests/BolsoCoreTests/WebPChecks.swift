import AppKit
import BolsoCore

func webPChecks() {
    // Generated lossless 32×24 WebP: red with one transparent pixel.
    let data = Data(base64Encoded: "UklGRiQAAABXRUJQVlA4TBgAAAAvH8AFEA8Q8x/zHwyBQOIv3QIDRPQ/dQc=")!
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    for type in [ImagePayload.webPType, NSPasteboard.PasteboardType("image/webp")] {
        board.clearContents()
        board.setData(data, forType: type)
        let clip = Clip.read(from: board)!
        let image = clip.editableImage!
        precondition(image.width == 32 && image.height == 24)
        let decoded = image.decode()!
        let output = ImageAnnotationRenderer.png(image: decoded, annotations: [])!
        let bitmap = NSBitmapImageRep(data: output)!
        precondition(bitmap.pixelsWide == 32 && bitmap.pixelsHigh == 24)
        precondition(bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0)
        precondition(bitmap.colorAt(x: 10, y: 10)!.redComponent > 0.9)
        precondition(clip.write(to: board, plain: false))
        precondition(board.data(forType: type) == data)
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("bolso-test-\(UUID()).WEBP")
    defer { try? FileManager.default.removeItem(at: url) }
    try! data.write(to: url)
    board.clearContents(); board.writeObjects([url as NSURL])
    let file = Clip.read(from: board)!
    guard case .files(let urls) = file.payload else { fatalError("File paste semantics changed") }
    precondition(urls == [url] && file.editableImage != nil)
    precondition(file.imageByteCount > data.count)
    precondition(file.write(to: board, plain: false))
    precondition(file.write(to: board, plain: true))
    precondition(board.string(forType: .string) == url.path)
    try! Data("invalid webp".utf8).write(to: url)
    precondition(ImagePayload.readWebPFile(url) == nil)
    precondition(file.editableImage!.decode() != nil, "Snapshot must survive file changes")
    try! FileManager.default.removeItem(at: url)
    precondition(ImagePayload.readWebPFile(url) == nil)
    precondition(!file.write(to: board, plain: false))
    print("PASS: WebP clipboard UTI/MIME, Finder snapshot, PNG export, alpha and invalid files")
}
