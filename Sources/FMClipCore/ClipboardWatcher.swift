import AppKit

/// Does a check of the pasteboard change count on a timer. macOS sends no event when the clipboard changes.
/// Calls `onCapture` with the FileMaker objects of each new clipboard contents. Contents with no FileMaker class
/// call `onOther` (for example, plain text).
///
/// The change count changes on `clearContents` and `declareTypes`, not on each `setData`. A tool that sets the data of
/// the classes one by one can add data after the check. So for `settleTime` after a change, each check reads the
/// FileMaker objects again. If they are not the same as at the last read (for example, `FOPN` came after the FileMaker
/// class), the watcher calls `onCapture` again. The history then updates the same entry with the name and the folder.
public final class ClipboardWatcher {
    /// The time after a change while the watcher still reads the same contents again, in seconds.
    public static let settleTime: TimeInterval = 2
    public let pasteboard: NSPasteboard
    public let interval: TimeInterval
    private let onCapture: ([FMObject]) -> Void
    private let onOther: (() -> Void)?
    private var lastChangeCount: Int
    private var timer: Timer?
    /// The FileMaker objects of the current clipboard contents, at the last read.
    private var lastObjects: [FMObject] = []
    /// The end of the time to read the same contents again, or nil.
    private var settleUntil: Date?
    /// The clock (tests can change it).
    var now: () -> Date = Date.init

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
        if changeCount > lastChangeCount {
            lastChangeCount = changeCount
            settleUntil = nil
        }
    }

    /// Does one check now. Returns the captured objects (empty if there is no change or no FileMaker class).
    @discardableResult
    public func poll() -> [FMObject] {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return recheck() }
        lastChangeCount = count
        settleUntil = now().addingTimeInterval(Self.settleTime)
        let objects = FMPasteboard.read(pasteboard)
        lastObjects = objects
        if objects.isEmpty { onOther?() } else { onCapture(objects) }
        return objects
    }

    /// The same change count as at the last check: in the settle time, reads the clipboard again. Calls `onCapture`
    /// only if the FileMaker objects, their names or their folders are not the same as at the last read.
    private func recheck() -> [FMObject] {
        guard let until = settleUntil else { return [] }
        guard now() <= until else {
            settleUntil = nil
            return []
        }
        let objects = FMPasteboard.read(pasteboard)
        guard objects != lastObjects else { return [] }
        lastObjects = objects
        if !objects.isEmpty { onCapture(objects) }
        return objects
    }
}
