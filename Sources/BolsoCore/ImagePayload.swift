import AppKit
import ImageIO
import UniformTypeIdentifiers

public struct ImagePayload {
    public static let webPType = NSPasteboard.PasteboardType(UTType.webP.identifier)
    public static let byteLimit = 32 * 1_024 * 1_024
    public static let pixelLimit = 24_000_000
    public static let historyBudget = 128 * 1_024 * 1_024
    public let original: Data?
    public let type: NSPasteboard.PasteboardType
    public let thumbnail: Data
    public let width: Int
    public let height: Int
    public var canEdit: Bool { original != nil }
    public var byteCount: Int { (original?.count ?? 0) + thumbnail.count }

    public init?(data: Data, type: NSPasteboard.PasteboardType = .png) {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0,
              let thumbnail = Clip.thumbnail(from: data) else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        self.width = (5...8).contains(orientation) ? h : w
        self.height = (5...8).contains(orientation) ? w : h
        self.thumbnail = thumbnail
        self.type = type
        original = data.count <= Self.byteLimit && w <= Self.pixelLimit / h ? data : nil
    }

    // Keep a bounded snapshot for editing; pasting the item still uses its file URL.
    public static func readWebPFile(_ url: URL) -> ImagePayload? {
        guard url.isFileURL, url.pathExtension.lowercased() == "webp",
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= byteLimit,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: byteLimit + 1), data.count <= byteLimit else { return nil }
        return ImagePayload(data: data, type: webPType)
    }

    public func decode() -> CGImage? {
        guard let original, let source = CGImageSourceCreateWithData(original as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}
