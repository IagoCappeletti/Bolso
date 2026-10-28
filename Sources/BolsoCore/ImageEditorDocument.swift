import AppKit
import Combine

public enum AnnotationTool: String, CaseIterable {
    case pen = "Desenhar", highlighter = "Marcador", arrow = "Seta", rectangle = "Caixa", ellipse = "Círculo", text = "Texto", counter = "Número", blur = "Desfocar"
    public var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .counter: return "1.circle"
        case .blur: return "square.grid.3x3.fill"
        }
    }
}

public struct Annotation: Identifiable {
    public let id = UUID()
    public var tool: AnnotationTool
    public var points: [CGPoint]
    public var color: NSColor
    public var width: CGFloat
    public var text: String
    public var fontSize: CGFloat
    /// Text drawn on a filled box in its color.
    public var background: Bool
    public var number: Int
    public init(tool: AnnotationTool, points: [CGPoint], color: NSColor, width: CGFloat, text: String = "", fontSize: CGFloat = 28, background: Bool = false, number: Int = 0) {
        self.tool = tool; self.points = points; self.color = color; self.width = width
        self.text = text; self.fontSize = fontSize; self.background = background; self.number = number
    }
}

public final class ImageEditorDocument: ObservableObject {
    @Published public private(set) var image: CGImage
    @Published public private(set) var annotations: [Annotation] = []
    @Published public private(set) var redoStack: [Annotation] = []
    private var delivered: [UUID] = []
    public init(image: CGImage) { self.image = image }
    public var isDirty: Bool { annotations.map(\.id) != delivered }
    public var nextNumber: Int { (annotations.filter { $0.tool == .counter }.map(\.number).max() ?? 0) + 1 }
    /// Swaps the base image while nothing is drawn on it, as when a capture region is adjusted.
    @discardableResult public func replaceImage(_ image: CGImage) -> Bool {
        guard annotations.isEmpty else { return false }
        self.image = image; redoStack.removeAll()
        return true
    }
    public func add(_ annotation: Annotation) {
        guard let first = annotation.points.first, let last = annotation.points.last else { return }
        if annotation.tool == .text && annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        if annotation.tool == .arrow && first == last { return }
        if [.rectangle, .ellipse, .blur].contains(annotation.tool) && (first.x == last.x || first.y == last.y) { return }
        annotations.append(annotation); redoStack.removeAll()
    }
    public func undo() { if let last = annotations.popLast() { redoStack.append(last) } }
    public func redo() { if let last = redoStack.popLast() { annotations.append(last) } }
    public func markDelivered() { delivered = annotations.map(\.id) }
}
