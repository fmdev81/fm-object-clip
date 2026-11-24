import AppKit

/// Does a check of the pasteboard change count on a timer. macOS sends no event when the clipboard changes.
/// Calls `onCapture` with the FileMaker objects of each new clipboard contents. Contents with no FileMaker class
/// call `onOther` (for example, plain text).
public final class ClipboardWatcher {
    public let pasteboard: NSPasteboard
    public let interval: TimeInterval
    private let onCapture: ([FMObject]) -> Void
    private let onOther: (() -> Void)?
    private var lastChangeCount: Int
    private var timer: Timer?

    public init(pasteboard: NSPasteboard = .general, interval: TimeInterval = 0.4,
                onOther: (() -> Void)? = nil, onCapture: @escaping ([FMObject]) -> Void) {
        self.pasteboard = pasteboard
        self.interval = interval
        self.onCapture = onCapture
        self.onOther = onOther
        self.lastChangeCount = pasteboard.changeCount
    }

    /// Starts the timer on the current run loop.
    public func start() {
        stop()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.current.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Ignores the clipboard contents of this change count, for example a copy from the app itself.
    public func ignore(changeCount: Int) {
        if changeCount > lastChangeCount { lastChangeCount = changeCount }
    }

    /// Does one check now. Returns the captured objects (empty if there is no change or no FileMaker class).
    @discardableResult
    public func poll() -> [FMObject] {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return [] }
        lastChangeCount = count
        let objects = FMPasteboard.read(pasteboard)
        if objects.isEmpty { onOther?() } else { onCapture(objects) }
        return objects
    }
}
