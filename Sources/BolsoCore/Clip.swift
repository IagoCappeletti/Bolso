import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

public struct Clip: Identifiable {
    public enum Payload {
        case text(String, rtf: Data?)
        case image(ImagePayload)
        case files([URL])
    }
    public let id = UUID()
    public let copiedAt = Date()
    public let fingerprint: String
    public let payload: Payload
    private let fileImage: ImagePayload?
    private init(fingerprint: String, payload: Payload, fileImage: ImagePayload? = nil) {
        self.fingerprint = fingerprint
        self.payload = payload
        self.fileImage = fileImage
    }
    public var text: String {
        switch payload {
        case .text(let text, _): return text
        case .image(let image): return image.canEdit ? "Imagem" : "Imagem (somente miniatura)"
        case .files(let urls): return urls.map(\.path).joined(separator: "\n")
        }
    }
    public var preview: String { String(text.prefix(240)) }
    public var canPastePlain: Bool { if case .image = payload { return false }; return true }
    public static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    public static let textLimit = 1_048_576
    public static func read(from board: NSPasteboard) -> Clip? {
        guard !(board.types ?? []).contains(concealed),
              !(board.pasteboardItems ?? []).contains(where: { $0.types.contains(concealed) }) else { return nil }
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            guard urls.count <= 1024 else { return nil }
            let identity = urls.map(\.absoluteString).joined(separator: "\n")
            return Clip(fingerprint: "files:" + digest(Data(identity.utf8)), payload: .files(urls), fileImage: urls.count == 1 ? ImagePayload.readWebPFile(urls[0]) : nil)
        }
        for type in [ImagePayload.webPType, NSPasteboard.PasteboardType("image/webp"), .png, .tiff] {
            if let data = board.data(forType: type), let image = ImagePayload(data: data, type: type) {
                return Clip(fingerprint: "image:" + digest(data), payload: .image(image))
            }
        }
        guard let text = board.string(forType: .string), !text.isEmpty, text.utf8.count <= textLimit else { return nil }
        let rich = board.data(forType: .rtf).flatMap { $0.count <= textLimit ? $0 : nil }
        return Clip(fingerprint: "text:" + digest(Data(text.utf8)), payload: .text(text, rtf: rich))
    }
    public static func thumbnail(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return result as Data
    }
    @discardableResult public func write(to board: NSPasteboard, plain: Bool) -> Bool {
        guard !plain || canPastePlain else { return false }
        if case .files(let urls) = payload, !plain,
           urls.contains(where: { !FileManager.default.fileExists(atPath: $0.path) }) { return false }
        board.clearContents()
        if plain { return board.setString(text, forType: .string) }
        switch payload {
        case .text(let text, let rtf):
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            if let rtf { item.setData(rtf, forType: .rtf) }
            return board.writeObjects([item])
        case .image(let image): return board.setData(image.original ?? image.thumbnail, forType: image.original == nil ? .png : image.type)
        case .files(let urls): return board.writeObjects(urls.map { $0 as NSURL })
        }
    }
    public var imagePreview: ImagePayload? {
        if case .image(let image) = payload { return image }
        return fileImage
    }
    public var editableImage: ImagePayload? {
        guard let image = imagePreview, image.canEdit else { return nil }
        return image
    }
    public var imageByteCount: Int {
        imagePreview?.byteCount ?? 0
    }
    public static func plainText(_ text: String) -> Clip? {
        guard !text.isEmpty, text.utf8.count <= textLimit else { return nil }
        return Clip(fingerprint: "text:" + digest(Data(text.utf8)), payload: .text(text, rtf: nil))
    }
    public static func renderedImage(_ png: Data) -> Clip? {
        guard let image = ImagePayload(data: png), image.canEdit else { return nil }
        return Clip(fingerprint: "image:" + digest(png), payload: .image(image))
    }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// What the history list shows for each item.
extension Clip {
    public enum Kind { case text, link, files, image }

    public var kind: Kind {
        switch payload {
        case .image: return .image
        case .files: return .files
        case .text: return link == nil ? .text : .link
        }
    }

    /// One line for the list: whitespace folded, links without scheme and query, files by name.
    public var title: String {
        switch payload {
        case .image: return "Imagem"
        case .files(let urls):
            let name = urls.first?.lastPathComponent ?? ""
            return urls.count > 1 ? "\(name) e mais \(urls.count - 1)" : name
        case .text(let text, _):
            guard let link else { return text.prefix(400).split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            let host = link.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? ""
            let path = link.path.hasSuffix("/") ? String(link.path.dropLast()) : link.path
            return host + path
        }
    }

    public var kindLabel: String {
        switch payload {
        case .text: return link == nil ? "Texto" : "Link"
        case .image(let image): return Self.size(image)
        case .files(let urls):
            guard urls.count == 1, let url = urls.first else { return "\(urls.count) arquivos" }
            if url.hasDirectoryPath { return "Pasta" }
            let type = url.pathExtension.isEmpty ? "Arquivo" : url.pathExtension.uppercased()
            return fileImage.map { "\(type) · \(Self.size($0))" } ?? type
        }
    }

    public func age(at now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(copiedAt))
        switch seconds {
        case ..<60: return "agora"
        case ..<3600: return "há \(Int(seconds / 60)) min"
        case ..<86_400: return "há \(Int(seconds / 3600)) h"
        default:
            let days = Int(seconds / 86_400)
            return days == 1 ? "ontem" : "há \(days) dias"
        }
    }

    /// A single web address and nothing else; a sentence that contains one stays text.
    private var link: URL? {
        guard case .text(let text, _) = payload else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 2048, !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }

    private static let grouping: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .decimal
        return formatter
    }()
    private static func size(_ image: ImagePayload) -> String {
        func number(_ value: Int) -> String { grouping.string(from: NSNumber(value: value)) ?? "\(value)" }
        return "\(number(image.width)) × \(number(image.height)) px"
    }
}
