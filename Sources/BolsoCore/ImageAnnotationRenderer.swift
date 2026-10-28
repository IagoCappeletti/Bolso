import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum ImageAnnotationRenderer {
    // The caller supplies a context whose origin is the top-left of the image.
    public static func draw(image: CGImage, annotations: [Annotation], in context: CGContext) {
        let size = CGSize(width: image.width, height: image.height)
        context.saveGState()
        context.clip(to: CGRect(origin: .zero, size: size))
        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: size))
        context.restoreGState()
        for annotation in annotations { draw(annotation, over: image, in: context) }
        context.restoreGState()
    }

    private static func draw(_ a: Annotation, over image: CGImage, in c: CGContext) {
        guard let start = a.points.first, let end = a.points.last else { return }
        c.saveGState()
        defer { c.restoreGState() }
        c.setStrokeColor(a.color.cgColor); c.setFillColor(a.color.cgColor)
        c.setLineWidth(a.width); c.setLineCap(.round); c.setLineJoin(.round)
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x-start.x), height: abs(end.y-start.y))
        switch a.tool {
        case .pen, .highlighter:
            var width = a.width
            if a.tool == .highlighter {
                // One translucent path, multiplied so dark text under it stays dark.
                width *= 3
                c.setBlendMode(.multiply)
                c.setStrokeColor(a.color.withAlphaComponent(0.45).cgColor); c.setFillColor(a.color.withAlphaComponent(0.45).cgColor)
                c.setLineWidth(width)
            }
            if a.points.count == 1 { c.fillEllipse(in: CGRect(x: start.x-width/2, y: start.y-width/2, width: width, height: width)); return }
            c.addLines(between: a.points); c.strokePath()
        case .rectangle: c.stroke(rect)
        case .ellipse: c.strokeEllipse(in: rect)
        case .arrow:
            let angle = atan2(end.y-start.y, end.x-start.x), length = 16+a.width
            c.move(to: start); c.addLine(to: end)
            c.move(to: CGPoint(x: end.x-length*cos(angle-0.5), y: end.y-length*sin(angle-0.5)))
            c.addLine(to: end)
            c.addLine(to: CGPoint(x: end.x-length*cos(angle+0.5), y: end.y-length*sin(angle+0.5)))
            c.strokePath()
        case .blur: pixelate(image, in: rect, block: max(10, a.width * 4), context: c)
        case .text:
            let font = NSFont.systemFont(ofSize: a.fontSize, weight: .semibold)
            let origin = lineOrigin(centeredOn: start, font: font)
            if a.background {
                let pad = a.fontSize * 0.3
                let box = CGRect(origin: origin, size: (a.text as NSString).size(withAttributes: [.font: font])).insetBy(dx: -pad, dy: -pad / 2)
                c.addPath(CGPath(roundedRect: box, cornerWidth: pad, cornerHeight: pad, transform: nil)); c.fillPath()
            }
            drawString(a.text, at: origin, font: font, color: a.background ? contrasting(a.color) : a.color, in: c)
        case .counter:
            let diameter = 12 + a.width * 4
            let circle = CGRect(x: start.x - diameter/2, y: start.y - diameter/2, width: diameter, height: diameter)
            c.fillEllipse(in: circle)
            c.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor); c.setLineWidth(max(1.5, diameter / 16))
            c.strokeEllipse(in: circle)
            let font = NSFont.systemFont(ofSize: diameter * 0.55, weight: .bold), label = "\(a.number)"
            let width = (label as NSString).size(withAttributes: [.font: font]).width
            let origin = lineOrigin(centeredOn: start, font: font)
            drawString(label, at: CGPoint(x: start.x - width / 2, y: origin.y), font: font, color: contrasting(a.color), in: c)
        }
    }

    /// Top-left for draw(at:) so the line starts at the point with its capitals centered on it.
    private static func lineOrigin(centeredOn point: CGPoint, font: NSFont) -> CGPoint {
        CGPoint(x: point.x, y: point.y - font.ascender + font.capHeight / 2)
    }

    private static func drawString(_ string: String, at origin: CGPoint, font: NSFont, color: NSColor, in c: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
        (string as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: color])
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func contrasting(_ color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return .white }
        return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent > 0.6 ? .black : .white
    }

    /// Averages the base image into blocks; earlier marks in the area are covered too, so nothing under it survives export.
    private static func pixelate(_ image: CGImage, in rect: CGRect, block: CGFloat, context c: CGContext) {
        let area = rect.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !area.isNull, area.width >= 1, area.height >= 1, let crop = image.cropping(to: area),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let columns = max(1, Int((area.width / block).rounded(.up))), rows = max(1, Int((area.height / block).rounded(.up)))
        guard let small = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        small.interpolationQuality = .high
        small.draw(crop, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        guard let blocks = small.makeImage() else { return }
        c.interpolationQuality = .none
        c.translateBy(x: area.minX, y: area.maxY); c.scaleBy(x: 1, y: -1)
        c.draw(blocks, in: CGRect(origin: .zero, size: area.size))
    }

    public static func render(image: CGImage, annotations: [Annotation]) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(image.height)); context.scaleBy(x: 1, y: -1)
        draw(image: image, annotations: annotations, in: context)
        return context.makeImage()
    }

    public static func png(image: CGImage, annotations: [Annotation]) -> Data? {
        guard let result = render(image: image, annotations: annotations) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, result, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
