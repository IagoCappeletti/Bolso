import CoreGraphics
import Foundation
import Vision

public enum TextRecognizer {
    /// Serial, so a request made during warm-up waits for it instead of preparing the model a second time.
    private static let queue = DispatchQueue(label: "dev.personal.Bolso.text-recognizer", qos: .userInitiated)
    /// Main thread only: whether macOS has prepared the model for this binary yet.
    public private(set) static var isPrepared = false

    /// The first recognition by a newly installed binary waits for macOS to prepare the model, which can take a minute.
    public static func warmUp() {
        queue.async(qos: .utility) {
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let context = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
            _ = context.makeImage().flatMap(text(in:))
            DispatchQueue.main.async { isPrepared = true }
        }
    }

    /// Prepares the image off the main thread and reports on the main thread.
    public static func recognize(_ image: @escaping () -> CGImage?, completion: @escaping (String?) -> Void) {
        queue.async {
            let result = autoreleasepool { image().flatMap(text(in:)) }
            DispatchQueue.main.async { isPrepared = true; completion(result) }
        }
    }

    /// Blocks the calling thread.
    public static func text(in image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        request.recognitionLanguages = ["pt-BR", "en-US"].filter(supported.contains)
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return nil }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
