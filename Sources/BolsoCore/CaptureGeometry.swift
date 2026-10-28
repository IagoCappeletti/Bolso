import Foundation

public struct CaptureEdges: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let left = CaptureEdges(rawValue: 1), right = CaptureEdges(rawValue: 2)
    public static let top = CaptureEdges(rawValue: 4), bottom = CaptureEdges(rawValue: 8)
}

/// All rectangles here use a top-left origin, local to a single display.
public enum CaptureGeometry {
    public static func selection(from start: CGPoint, to end: CGPoint, in bounds: CGRect) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
    }

    public static func edges(at point: CGPoint, of rect: CGRect, tolerance: CGFloat = 6) -> CaptureEdges {
        guard rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { return [] }
        var edges: CaptureEdges = []
        let left = abs(point.x - rect.minX), right = abs(point.x - rect.maxX)
        if min(left, right) <= tolerance { edges.insert(left <= right ? .left : .right) }
        let top = abs(point.y - rect.minY), bottom = abs(point.y - rect.maxY)
        if min(top, bottom) <= tolerance { edges.insert(top <= bottom ? .top : .bottom) }
        return edges
    }

    /// Crossing the opposite edge flips the rect instead of collapsing it.
    public static func resize(_ rect: CGRect, edges: CaptureEdges, to point: CGPoint, in bounds: CGRect) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if edges.contains(.left) { minX = point.x }
        if edges.contains(.right) { maxX = point.x }
        if edges.contains(.top) { minY = point.y }
        if edges.contains(.bottom) { maxY = point.y }
        return selection(from: CGPoint(x: minX, y: minY), to: CGPoint(x: maxX, y: maxY), in: bounds)
    }

    /// Shifts the rect with the pointer in whole points, so its pixel size never drifts, and keeps it on the display.
    public static func move(_ rect: CGRect, from start: CGPoint, to point: CGPoint, in bounds: CGRect) -> CGRect {
        let x = min(max(rect.minX + (point.x - start.x).rounded(), bounds.minX), bounds.maxX - rect.width)
        let y = min(max(rect.minY + (point.y - start.y).rounded(), bounds.minY), bounds.maxY - rect.height)
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    /// The move grip sits inside the top edge, clear of the resize handles and of a toolbar on either side;
    /// regions too small to hold it carry it just outside.
    public static func moveGrip(for selection: CGRect, in bounds: CGRect) -> CGRect {
        let size = CGSize(width: 44, height: 20), gap: CGFloat = 12
        var y = selection.minY + gap
        if selection.width < size.width + gap * 2 || selection.height < size.height + gap * 2 {
            y = selection.minY - gap - size.height >= bounds.minY ? selection.minY - gap - size.height : selection.maxY + gap
        }
        let x = min(max(selection.midX - size.width / 2, bounds.minX), bounds.maxX - size.width)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// CGWindowList bounds use a top-left origin at the primary display's corner.
    public static func localRect(forWindowBounds bounds: CGRect, primaryHeight: CGFloat, screenFrame: CGRect) -> CGRect {
        CGRect(x: bounds.minX - screenFrame.minX, y: bounds.minY - (primaryHeight - screenFrame.maxY), width: bounds.width, height: bounds.height)
    }

    public static func pixelRect(for selection: CGRect, displaySize: CGSize, imageSize: CGSize) -> CGRect? {
        guard displaySize.width > 0, displaySize.height > 0, imageSize.width > 0, imageSize.height > 0 else { return nil }
        let clipped = selection.standardized.intersection(CGRect(origin: .zero, size: displaySize))
        guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else { return nil }
        let sx = imageSize.width / displaySize.width, sy = imageSize.height / displaySize.height
        let rect = CGRect(x: floor(clipped.minX * sx), y: floor(clipped.minY * sy),
                          width: ceil(clipped.maxX * sx) - floor(clipped.minX * sx),
                          height: ceil(clipped.maxY * sy) - floor(clipped.minY * sy))
        return rect.intersection(CGRect(origin: .zero, size: imageSize))
    }

    public static func displayRect(for pixels: CGRect, displaySize: CGSize, imageSize: CGSize) -> CGRect {
        CGRect(x: pixels.minX * displaySize.width / imageSize.width,
               y: pixels.minY * displaySize.height / imageSize.height,
               width: pixels.width * displaySize.width / imageSize.width,
               height: pixels.height * displaySize.height / imageSize.height)
    }

    /// Window coordinates have a bottom-left origin, unlike the selection canvas.
    public static func globalRect(for localRect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.minX + localRect.minX, y: screenFrame.maxY - localRect.maxY,
               width: localRect.width, height: localRect.height)
    }

    public static func toolbarFrame(size: CGSize, selection: CGRect, visibleFrame: CGRect) -> CGRect {
        let gap: CGFloat = 12
        let size = CGSize(width: min(size.width, visibleFrame.width), height: min(size.height, visibleFrame.height))
        let x = min(max(selection.minX, visibleFrame.minX), visibleFrame.maxX - size.width)
        let y: CGFloat
        if selection.minY - gap - size.height >= visibleFrame.minY {
            y = selection.minY - gap - size.height
        } else if selection.maxY + gap + size.height <= visibleFrame.maxY {
            y = selection.maxY + gap
        } else {
            y = min(max(selection.minY + gap, visibleFrame.minY), visibleFrame.maxY - size.height)
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
