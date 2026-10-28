import AppKit
import BolsoCore

func toolChecks() {
    // White canvas, a black square for the highlighter and fine stripes for pixelation.
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 400, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    memset(bitmap.bitmapData!, 255, bitmap.bytesPerRow * bitmap.pixelsHigh)
    for y in 0..<400 {
        for x in 0..<600 where (x >= 20 && x < 60 && y >= 20 && y < 60) || (x >= 300 && x < 400 && y >= 100 && y < 200 && x % 2 == 0) {
            let pixel = bitmap.bitmapData!.advanced(by: y * bitmap.bytesPerRow + x * 4)
            pixel[0] = 0; pixel[1] = 0; pixel[2] = 0
        }
    }
    let document = ImageEditorDocument(image: bitmap.cgImage!)
    let yellow = NSColor.systemYellow
    document.add(Annotation(tool: .highlighter, points: [CGPoint(x: 10, y: 40), CGPoint(x: 120, y: 40)], color: yellow, width: 6))
    document.add(Annotation(tool: .blur, points: [CGPoint(x: 400, y: 200), CGPoint(x: 300, y: 100)], color: .red, width: 5))
    document.add(Annotation(tool: .blur, points: [CGPoint(x: 500, y: 300), CGPoint(x: 500, y: 350)], color: .red, width: 5))
    precondition(document.annotations.count == 2, "Zero-width blur must be discarded")
    precondition(document.nextNumber == 1)
    document.add(Annotation(tool: .counter, points: [CGPoint(x: 200, y: 300)], color: .systemRed, width: 5, number: document.nextNumber))
    document.add(Annotation(tool: .counter, points: [CGPoint(x: 280, y: 300)], color: .systemYellow, width: 5, number: document.nextNumber))
    precondition(document.annotations.suffix(2).map(\.number) == [1, 2] && document.nextNumber == 3)
    document.undo(); precondition(document.nextNumber == 2, "Undone steps free their number")
    document.redo()
    document.add(Annotation(tool: .text, points: [CGPoint(x: 420, y: 330)], color: .systemRed, width: 5, text: "Aviso", fontSize: 30, background: true))
    precondition(!document.replaceImage(bitmap.cgImage!), "Base image is locked once marks exist")
    let result = NSBitmapImageRep(data: ImageAnnotationRenderer.png(image: document.image, annotations: document.annotations)!)!
    func rgb(_ x: Int, _ y: Int) -> (CGFloat, CGFloat, CGFloat) {
        let c = result.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        return (c.redComponent, c.greenComponent, c.blueComponent)
    }
    let tinted = rgb(100, 40), dark = rgb(40, 40)
    precondition(tinted.0 > 0.8 && tinted.1 > 0.6 && tinted.2 < 0.75, "Highlighter must tint white yellow")
    precondition(dark.0 < 0.1 && dark.1 < 0.1 && dark.2 < 0.1, "Highlighter must keep dark content dark")
    let block = (0..<20).flatMap { dy in (0..<20).map { dx in rgb(300 + dx, 100 + dy).0 } }
    precondition(Set(block.map { Int($0 * 255) }).count == 1, "A pixelated block must be one flat color")
    precondition(block[0] > 0.3 && block[0] < 0.7, "Stripes must average to gray, not survive")
    precondition(rgb(189, 300).0 > 0.8 && rgb(189, 300).1 < 0.4, "Counter fill uses its color")
    var digitPixels = 0
    for y in 290..<310 { for x in 194..<206 where rgb(x, y).1 > 0.9 && rgb(x, y).2 > 0.9 { digitPixels += 1 } }
    precondition(digitPixels > 10, "Counter digit must contrast with a red fill")
    var darkDigit = 0
    for y in 290..<310 { for x in 274..<286 where rgb(x, y).0 < 0.3 { darkDigit += 1 } }
    precondition(darkDigit > 10, "Counter digit on yellow must be dark")
    precondition(rgb(415, 330).0 > 0.8 && rgb(415, 330).1 < 0.4, "Text background must fill around the line start")
    var light = 0
    for y in 320..<340 { for x in 425..<500 where rgb(x, y).1 > 0.9 { light += 1 } }
    precondition(light > 30, "Text on a red box must be light")

    let fresh = ImageEditorDocument(image: bitmap.cgImage!)
    let crop = bitmap.cgImage!.cropping(to: CGRect(x: 0, y: 0, width: 50, height: 40))!
    precondition(fresh.replaceImage(crop) && fresh.image.width == 50, "An untouched capture can be re-cropped")

    let white = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 200, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    memset(white.bitmapData!, 255, white.bytesPerRow * white.pixelsHigh)
    let line = Annotation(tool: .text, points: [CGPoint(x: 30, y: 100)], color: .black, width: 5, text: "Licitação aberta 2026", fontSize: 64)
    let page = NSBitmapImageRep(data: ImageAnnotationRenderer.png(image: white.cgImage!, annotations: [line])!)!.cgImage!
    let recognized = TextRecognizer.text(in: page) ?? ""
    precondition(recognized.contains("2026") && recognized.localizedCaseInsensitiveContains("aberta"), "OCR must read the rendered line, got: \(recognized)")
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    precondition(Clip.plainText("") == nil)
    let clip = Clip.plainText(recognized)!
    precondition(clip.write(to: board, plain: false) && board.string(forType: .string) == recognized)
    print("PASS: marcador, pixelização, números, texto com fundo, recorte ajustável, OCR e texto copiado")
}
