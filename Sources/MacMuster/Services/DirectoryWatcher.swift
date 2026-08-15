import Foundation

/// Watches directory trees and reports changes that look like an app being installed or removed.
///
/// Uses FSEvents rather than a `DispatchSource` per directory: one kernel subscription covers a
/// whole tree, it survives the watched directory being replaced, and it coalesces bursts — an
/// app install touches hundreds of paths and should produce one callback, not hundreds.
///
/// The callback arrives on a background queue. Callers are expected to hop to whatever isolation
/// they need and to debounce further; this type deliberately does no scheduling of its own.
final class DirectoryWatcher {

    /// How long FSEvents batches events before delivering. Paired with `kFSEventStreamCreateFlagNoDefer`
    /// the first event in a quiet period is delivered immediately and the rest of the burst is
    /// throttled, which is what makes a fresh install register promptly instead of at the end
    /// of a long copy.
    private static let latencySeconds: CFTimeInterval = 0.5

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.macmuster.directory-watcher", qos: .utility)
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    /// Starts watching `paths`, replacing any previous subscription. Passing an empty array
    /// just stops watching.
    func start(paths: [String]) {
        stop()

        let existing = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .compactMap(Self.canonicalPath)
        guard !existing.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // `eventPaths` is a CFArray of CFString only because of `kFSEventStreamCreateFlagUseCFTypes`
        // below. Without that flag it arrives as a `char **`, and bridging it as an NSArray
        // silently yields no paths at all rather than failing outright.
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            watcher.handleEvents(paths)
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            existing as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latencySeconds,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes
                    | kFSEventStreamCreateFlagNoDefer
                    | kFSEventStreamCreateFlagIgnoreSelf
            )
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil

        // `info` in the stream context is an unretained pointer to `self`. Invalidate stops any
        // *new* callback from being scheduled, but one already dispatched to `queue` can still be
        // mid-flight; without this drain, a caller that nils its reference to us right after
        // `stop()` returns (see `LibraryScanState.cleanupTimerAndObservers`) can free `self` while
        // that callback is still dereferencing the pointer. `queue` is serial and the callback
        // itself runs on `queue`, so an empty sync block here only returns once anything already
        // running or queued ahead of it — including that callback — has finished.
        queue.sync {}
    }

    private func handleEvents(_ paths: [String]) {
        guard paths.contains(where: { !Self.isInsideAppBundle($0) }) else { return }
        onChange()
    }

    /// Fully resolves a path, following symlinks in every component.
    ///
    /// FSEvents reports and matches against real paths, so a stream rooted at a symlinked path
    /// silently delivers nothing. `/var` → `/private/var` is the case that bites in practice —
    /// and neither `NSString.resolvingSymlinksInPath` nor `URL.resolvingSymlinksInPath()` will
    /// resolve it, since both deliberately leave `/private` prefixes alone. Only `realpath(3)`
    /// does. Relevant beyond temp directories: a user-added scan directory can sit behind a
    /// symlink to another volume.
    static func canonicalPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// True when the change happened *within* an app bundle rather than alongside one.
    ///
    /// FSEvents watches whole trees, so an app rewriting its own resources reports paths like
    /// `/Applications/Foo.app/Contents/Resources`. Those are ordinary app usage, not installs,
    /// and rescanning on them would mean a rescan every time any installed app touches itself.
    /// A bundle being created or deleted reports the *containing* directory, which has no `.app`
    /// component before its last one, so it still gets through.
    static func isInsideAppBundle(_ path: String) -> Bool {
        // FSEvents reports directories with a trailing slash ("/Applications/Foo.app/"), and
        // `pathComponents` turns that into a final "/" element. Dropping those first keeps
        // `dropLast()` aligned with the real last component — otherwise it shifts by one and a
        // newly created bundle is misjudged as churn *inside* a bundle, filtering out the very
        // install this watcher exists to catch.
        let components = (path as NSString).pathComponents.filter { $0 != "/" }
        return components.dropLast().contains { $0.hasSuffix(".app") }
    }
}
