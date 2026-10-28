import AppKit
import BolsoCore
import ImageIO
import UniformTypeIdentifiers

func editorChecks() {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3000, pixelsHigh: 2000, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    memset(bitmap.bitmapData!, 0, bitmap.bytesPerRow * bitmap.pixelsHigh)
    let pixel = bitmap.bitmapData!.advanced(by: 100 * bitmap.bytesPerRow + 200 * 4)
    pixel[0] = 0; pixel[1] = 0; pixel[2] = 255; pixel[3] = 255
    let png = bitmap.representation(using: .png, properties: [:])!
    let payload = ImagePayload(data: png)!
    precondition(payload.canEdit && payload.width == 3000 && payload.height == 2000)
    let rotatedData = NSMutableData()
    let rotatedDestination = CGImageDestinationCreateWithData(rotatedData, UTType.tiff.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(rotatedDestination, bitmap.cgImage!, [kCGImagePropertyOrientation: 6] as CFDictionary)
    precondition(CGImageDestinationFinalize(rotatedDestination))
    let rotated = ImagePayload(data: rotatedData as Data, type: .tiff)!
    precondition(rotated.width == 2000 && rotated.height == 3000)
    let decodedRotated = rotated.decode()!
    precondition(decodedRotated.width == 2000 && decodedRotated.height == 3000)
    let rotatedPNG = NSBitmapImageRep(data: ImageAnnotationRenderer.png(image: decodedRotated, annotations: [])!)!
    precondition(rotatedPNG.colorAt(x: 1899, y: 200)!.blueComponent > 0.9, "EXIF orientation must rotate pixels")
    let document = ImageEditorDocument(image: payload.decode()!)
    let line = Annotation(tool: .pen, points: [CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 50)], color: .red, width: 8)
    document.add(line)
    precondition(document.isDirty && document.annotations.count == 1)
    document.markDelivered(); precondition(!document.isDirty)
    document.undo(); precondition(document.isDirty && document.annotations.isEmpty)
    document.redo(); precondition(!document.isDirty && document.annotations.count == 1)
    document.undo(); document.add(line); precondition(document.redoStack.isEmpty)
    document.add(Annotation(tool: .text, points: [.zero], color: .black, width: 5, text: "  "))
    document.add(Annotation(tool: .rectangle, points: [.zero, .zero], color: .black, width: 5))
    precondition(document.annotations.count == 1)
    document.add(Annotation(tool: .rectangle, points: [CGPoint(x: 400, y: 400), CGPoint(x: 300, y: 300)], color: .green, width: 8))
    document.add(Annotation(tool: .text, points: [CGPoint(x: 500, y: 200)], color: .black, width: 5, text: "Olá ação", fontSize: 40))
    document.add(Annotation(tool: .arrow, points: [CGPoint(x: 800, y: 400), CGPoint(x: 700, y: 300)], color: .red, width: 8))
    document.add(Annotation(tool: .ellipse, points: [CGPoint(x: 900, y: 300), CGPoint(x: 1000, y: 400)], color: .green, width: 8))
    document.add(Annotation(tool: .text, points: [CGPoint(x: 1500, y: 1000)], color: .black, width: 5, text: "HH", fontSize: 40))
    let output = ImageAnnotationRenderer.png(image: document.image, annotations: document.annotations)!
    let result = NSBitmapImageRep(data: output)!
    precondition(result.pixelsWide == 3000 && result.pixelsHigh == 2000)
    precondition(result.colorAt(x: 100, y: 50)!.redComponent > 0.9, "Line must be at top, not vertically mirrored")
    precondition(result.colorAt(x: 200, y: 100)!.blueComponent > 0.9, "Original pixel must retain orientation")
    precondition(result.colorAt(x: 300, y: 350)!.greenComponent > 0.4, "Reverse rectangle must render")
    precondition(result.colorAt(x: 2000, y: 1000)!.alphaComponent == 0, "Transparency must survive")
    var textPixels = 0
    for y in 170..<230 { for x in 500..<700 { if result.colorAt(x: x, y: y)!.alphaComponent > 0.1 { textPixels += 1 } } }
    precondition(textPixels > 100, "Accented text must render around its anchor")
    var ink: [CGPoint] = []
    for y in 940..<1060 { for x in 1490..<1620 where result.colorAt(x: x, y: y)!.alphaComponent > 0.5 { ink.append(CGPoint(x: x, y: y)) } }
    let inkTop = ink.map(\.y).min()!, inkBottom = ink.map(\.y).max()!, inkLeft = ink.map(\.x).min()!
    precondition(abs((inkTop + inkBottom) / 2 - 1000) <= 3, "Text must be vertically centered on the click, not hang below it")
    precondition(inkLeft >= 1500 && inkLeft < 1510, "Text must start at the click")
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let edited = Clip.renderedImage(output)!
    precondition(edited.write(to: board, plain: false))
    precondition(Clip.read(from: board)!.fingerprint == edited.fingerprint)
    precondition(board.data(forType: .png) == output)
    var history = History<Int>(same: ==)
    [4, 0, 3, 2].forEach { history.insert($0) }
    history.trim(toByteBudget: 5, cost: { $0 })
    precondition(history.items == [2, 3, 0], "Eviction must retain non-image entries")
    var padded = png
    padded.append(Data(count: ImagePayload.byteLimit))
    let overLimit = ImagePayload(data: padded)!
    precondition(!overLimit.canEdit && overLimit.original == nil)
    precondition(ImagePayload(data: Data("invalid".utf8)) == nil)
    print("PASS: original 3000×2000, undo/redo, geometry, text, transparency, PNG copy and memory limits")
}
