import BolsoCore
import Foundation

func captureGeometryChecks() {
    let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let reversed = CaptureGeometry.selection(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 100, y: 50), in: display)
    precondition(reversed == CGRect(x: 100, y: 50, width: 200, height: 150), "Selection must accept any drag direction")
    let clipped = CaptureGeometry.selection(from: CGPoint(x: 1400, y: 880), to: CGPoint(x: 1600, y: 1000), in: display)
    precondition(clipped == CGRect(x: 1400, y: 880, width: 40, height: 20), "Selection must stay inside its display")

    let points = CGSize(width: 1440, height: 900), retina = CGSize(width: 2880, height: 1800)
    let pixels = CaptureGeometry.pixelRect(for: CGRect(x: 10.25, y: 20.5, width: 100.5, height: 50), displaySize: points, imageSize: retina)!
    precondition(pixels == CGRect(x: 20, y: 41, width: 202, height: 100), "Fractional points must snap outward to whole pixels")
    let aligned = CaptureGeometry.displayRect(for: pixels, displaySize: points, imageSize: retina)
    precondition(aligned == CGRect(x: 10, y: 20.5, width: 101, height: 50), "Canvas must cover exactly the cropped pixels")
    precondition(CaptureGeometry.pixelRect(for: CGRect(x: 5, y: 5, width: 1, height: 40), displaySize: points, imageSize: retina) == nil)
    precondition(CaptureGeometry.pixelRect(for: CGRect(x: 1430, y: 890, width: 50, height: 50), displaySize: points, imageSize: retina)
                 == CGRect(x: 2860, y: 1780, width: 20, height: 20))

    // A secondary display left of and below the primary one, as NSScreen reports it.
    let secondary = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
    let global = CaptureGeometry.globalRect(for: CGRect(x: 100, y: 80, width: 300, height: 200), screenFrame: secondary)
    precondition(global == CGRect(x: -1820, y: 500, width: 300, height: 200), "Top-left local rects must flip into global window space")

    let visible = CGRect(x: 0, y: 0, width: 1440, height: 875), bar = CGSize(width: 640, height: 150)
    let below = CaptureGeometry.toolbarFrame(size: bar, selection: CGRect(x: 200, y: 400, width: 300, height: 200), visibleFrame: visible)
    precondition(below == CGRect(x: 200, y: 238, width: 640, height: 150), "Toolbar goes under the selection when it fits")
    let above = CaptureGeometry.toolbarFrame(size: bar, selection: CGRect(x: 1200, y: 50, width: 200, height: 300), visibleFrame: visible)
    precondition(above == CGRect(x: 800, y: 362, width: 640, height: 150), "Toolbar flips above and stays on screen")
    let inside = CaptureGeometry.toolbarFrame(size: bar, selection: CGRect(x: 0, y: 0, width: 1440, height: 875), visibleFrame: visible)
    precondition(visible.contains(inside), "A full-screen selection keeps the toolbar visible")

    let picked = CGRect(x: 100, y: 100, width: 200, height: 100)
    precondition(CaptureGeometry.edges(at: CGPoint(x: 98, y: 203), of: picked) == [.left, .bottom], "Corner handles grab two edges")
    precondition(CaptureGeometry.edges(at: CGPoint(x: 200, y: 104), of: picked) == [.top])
    precondition(CaptureGeometry.edges(at: CGPoint(x: 200, y: 150), of: picked).isEmpty, "The interior stays free for drawing")
    precondition(CaptureGeometry.edges(at: CGPoint(x: 400, y: 150), of: picked).isEmpty)
    precondition(CaptureGeometry.edges(at: CGPoint(x: 14, y: 50), of: CGRect(x: 10, y: 40, width: 6, height: 30)) == [.right], "Thin rects pick the nearer side")
    precondition(CaptureGeometry.resize(picked, edges: [.right, .bottom], to: CGPoint(x: 350, y: 260), in: display) == CGRect(x: 100, y: 100, width: 250, height: 160))
    precondition(CaptureGeometry.resize(picked, edges: [.left], to: CGPoint(x: 360, y: 0), in: display) == CGRect(x: 300, y: 100, width: 60, height: 100), "Crossing the opposite edge flips")
    precondition(CaptureGeometry.resize(picked, edges: [.top], to: CGPoint(x: 0, y: -50), in: display) == CGRect(x: 100, y: 0, width: 200, height: 200), "Resizing stays on the display")
    precondition(CaptureGeometry.move(picked, from: CGPoint(x: 200, y: 110), to: CGPoint(x: 250.4, y: 89.6), in: display) == CGRect(x: 150, y: 80, width: 200, height: 100), "Moving keeps the size in whole-point steps")
    precondition(CaptureGeometry.move(picked, from: .zero, to: CGPoint(x: -500, y: 2000), in: display) == CGRect(x: 0, y: 800, width: 200, height: 100), "Moving stops at the display edges")
    let grip = CaptureGeometry.moveGrip(for: picked, in: display)
    precondition(picked.contains(grip) && grip.midX == picked.midX && grip.midY < picked.midY, "The move grip sits inside, near the top")
    precondition([CGPoint(x: grip.minX, y: grip.minY), CGPoint(x: grip.maxX, y: grip.maxY)].allSatisfy { CaptureGeometry.edges(at: $0, of: picked).isEmpty }, "The grip stays clear of the resize handles")
    for small in [CGRect(x: 100, y: 100, width: 40, height: 30), CGRect(x: 0, y: 0, width: 40, height: 30)] {
        let outside = CaptureGeometry.moveGrip(for: small, in: display)
        precondition(!outside.intersects(small.insetBy(dx: -6, dy: -6)) && display.contains(outside), "Small regions carry the grip outside, still on the display")
    }
    precondition(CaptureGeometry.localRect(forWindowBounds: CGRect(x: 100, y: 50, width: 300, height: 200), primaryHeight: 900, screenFrame: display) == CGRect(x: 100, y: 50, width: 300, height: 200))
    precondition(CaptureGeometry.localRect(forWindowBounds: CGRect(x: -1800, y: 200, width: 300, height: 200), primaryHeight: 900, screenFrame: secondary) == CGRect(x: 120, y: 80, width: 300, height: 200), "Window bounds must land on the secondary display")
    print("PASS: seleção, pixels Retina, alinhamento, várias telas, posição da barra, alças de ajuste, alça de mover e janelas")
}
