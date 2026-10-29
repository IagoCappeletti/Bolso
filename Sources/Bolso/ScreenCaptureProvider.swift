import AppKit
import ScreenCaptureKit
import BolsoCore

struct CaptureDisplay {
    let id: CGDirectDisplayID
    let frame: CGRect
    let visibleFrame: CGRect
    let pixelWidth: Int
    let pixelHeight: Int

    static func connected() -> [CaptureDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CaptureDisplay(id: id.uint32Value, frame: screen.frame, visibleFrame: screen.visibleFrame,
                                  pixelWidth: Int((screen.frame.width * screen.backingScaleFactor).rounded()),
                                  pixelHeight: Int((screen.frame.height * screen.backingScaleFactor).rounded()))
        }
    }
}

struct CapturedDisplay {
    let display: CaptureDisplay
    let image: CGImage
    /// Windows that were on this display, front to back, local to it with a top-left origin.
    var windows: [CGRect] = []
}

enum CaptureWindows {
    /// Front-to-back bounds of normal windows plus Bolso's own panels, in CGWindowList's global top-left space.
    static func onScreen() -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let own = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, let owner = info[kCGWindowOwnerPID as String] as? pid_t,
                  layer == 0 || (owner == own && layer < Int(CGWindowLevelForKey(.screenSaverWindow))),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.width >= 40, rect.height >= 40 else { return nil }
            return rect
        }
    }
    static func local(_ windows: [CGRect], on display: CaptureDisplay, primaryHeight: CGFloat) -> [CGRect] {
        let bounds = CGRect(origin: .zero, size: display.frame.size)
        return windows.compactMap { window in
            let rect = CaptureGeometry.localRect(forWindowBounds: window, primaryHeight: primaryHeight, screenFrame: display.frame).intersection(bounds)
            return rect.isNull || rect.width < 40 || rect.height < 40 ? nil : rect
        }
    }
}

enum ScreenCaptureFailure: LocalizedError {
    case unavailable, tooLarge, permission
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Não foi possível capturar a tela. Tente novamente."
        case .tooLarge: return "As telas conectadas excedem o limite de memória de captura (64 milhões de pixels). Reduza a resolução ou desconecte uma tela e tente novamente."
        case .permission: return "Ligue o Bolso em Ajustes do Sistema → Privacidade e Segurança → Gravação da Tela e tente de novo. O macOS pode pedir para reabrir o app."
        }
    }
}

enum ScreenCaptureProvider {
    static func capture(_ displays: [CaptureDisplay]) async throws -> [CapturedDisplay] {
        guard !displays.isEmpty else { throw ScreenCaptureFailure.unavailable }
        guard displays.reduce(0.0, { $0 + Double($1.pixelWidth) * Double($1.pixelHeight) }) <= 64_000_000 else { throw ScreenCaptureFailure.tooLarge }
        if #available(macOS 14.0, *) {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            var result: [CapturedDisplay] = []
            for display in displays {
                try Task.checkCancellation()
                guard let source = content.displays.first(where: { $0.displayID == display.id }) else { throw ScreenCaptureFailure.unavailable }
                let filter = SCContentFilter(display: source, excludingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.width = display.pixelWidth
                configuration.height = display.pixelHeight
                configuration.showsCursor = false
                configuration.capturesAudio = false
                configuration.captureResolution = .best
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                result.append(CapturedDisplay(display: display, image: image))
            }
            try Task.checkCancellation()
            return result
        }
        // macOS 13 has no SCScreenshotManager.
        return try await Task.detached(priority: .userInitiated) {
            try displays.map { display in
                guard let image = CGDisplayCreateImage(display.id) else { throw ScreenCaptureFailure.unavailable }
                return CapturedDisplay(display: display, image: image)
            }
        }.value
    }
}
