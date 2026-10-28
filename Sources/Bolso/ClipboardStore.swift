import AppKit
import Combine
import BolsoCore

final class ClipboardStore: ObservableObject {
    @Published private(set) var history = History<Clip>(same: { $0.fingerprint == $1.fingerprint })
    @Published private(set) var paused = false
    private var timer: Timer?
    private let board: NSPasteboard
    private var lastChange: Int
    var items: [Clip] { history.items }
    init(board: NSPasteboard = .general) {
        self.board = board
        lastChange = board.changeCount
        start()
    }
    private func start() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            autoreleasepool { self?.capture() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func togglePause() {
        paused.toggle()
        timer?.invalidate()
        timer = nil
        lastChange = board.changeCount
        if !paused { start() }
    }
    func clear() {
        history.clear()
        lastChange = board.changeCount
    }
    private func capture() {
        guard board.changeCount != lastChange else { return }
        lastChange = board.changeCount
        guard let clip = Clip.read(from: board), board.changeCount == lastChange else { return }
        remember(clip)
    }
    @discardableResult func write(_ clip: Clip, plain: Bool) -> Bool {
        guard clip.write(to: board, plain: plain) else { return false }
        lastChange = board.changeCount
        remember(clip)
        return true
    }
    private func remember(_ clip: Clip) {
        history.insert(clip)
        history.trim(toByteBudget: ImagePayload.historyBudget, cost: { $0.imageByteCount })
    }
    deinit {
        timer?.invalidate()
    }
}
