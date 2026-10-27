import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

public struct Clip: Identifiable {
    public enum Payload {
        case text(String, rtf: Data?)
        case image(Data) // Only a PNG thumbnail, never the original image.
        case files([URL])
    }
    public let id = UUID()
    public let fingerprint: String
    public let payload: Payload
    private init(fingerprint: String, payload: Payload) {
        self.fingerprint = fingerprint
        self.payload = payload
    }
    public var text: String {
        switch payload {
        case .text(let text, _): return text
        case .image: return "Imagem (miniatura)"
        case .files(let urls): return urls.map(\.path).joined(separator: "\n")
        }
    }
    public var preview: String { String(text.prefix(240)) }
    public var canPastePlain: Bool { if case .image = payload { return false }; return true }
    public func matches(_ query: String) -> Bool {
        query.isEmpty || text.localizedStandardContains(query)
    }
    public static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    public static let textLimit = 1_048_576
    public static func read(from board: NSPasteboard) -> Clip? {
        guard !(board.types ?? []).contains(concealed),
              !(board.pasteboardItems ?? []).contains(where: { $0.types.contains(concealed) }) else { return nil }
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            guard urls.count <= 1024 else { return nil }
            let identity = urls.map(\.absoluteString).joined(separator: "\n")
            return Clip(fingerprint: "files:" + digest(Data(identity.utf8)), payload: .files(urls))
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = board.data(forType: type), let thumbnail = thumbnail(from: data) {
                return Clip(fingerprint: "image:" + digest(data), payload: .image(thumbnail))
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
        case .image(let png): return board.setData(png, forType: .png)
        case .files(let urls): return board.writeObjects(urls.map { $0 as NSURL })
        }
    }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
