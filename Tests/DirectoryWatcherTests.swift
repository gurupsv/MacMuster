import XCTest
@testable import MacMuster

final class DirectoryWatcherTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MacMusterWatcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    // MARK: - Event filtering

    /// A bundle appearing or disappearing reports the *containing* directory, which must get
    /// through. Churn inside a bundle is an app rewriting its own resources and must not — every
    /// installed app doing that would mean a rescan storm.
    func testOnlyChangesOutsideAppBundlesCountAsInstalls() {
        XCTAssertFalse(DirectoryWatcher.isInsideAppBundle("/Applications"),
            "The scan root itself is where new bundles land")
        XCTAssertFalse(DirectoryWatcher.isInsideAppBundle("/Applications/SomeVendor"),
            "A vendor subdirectory is where nested installs land")
        XCTAssertFalse(DirectoryWatcher.isInsideAppBundle("/Applications/Foo.app"),
            "The bundle directory itself is the install event")

        XCTAssertTrue(DirectoryWatcher.isInsideAppBundle("/Applications/Foo.app/Contents"),
            "Churn inside a bundle is not an install")
        XCTAssertTrue(DirectoryWatcher.isInsideAppBundle("/Applications/Foo.app/Contents/Resources"),
            "Churn deep inside a bundle is not an install")
        XCTAssertTrue(DirectoryWatcher.isInsideAppBundle("/Applications/Xcode.app/Contents/Applications/Simulator.app"),
            "A nested bundle's own path still sits inside an outer bundle")
    }

    /// FSEvents delivers directory paths with a trailing slash, so the filter has to agree with
    /// the format it will actually be fed.
    func testFilterHandlesTheTrailingSlashFSEventsActuallySends() {
        XCTAssertFalse(DirectoryWatcher.isInsideAppBundle("/Applications/"))
        XCTAssertFalse(DirectoryWatcher.isInsideAppBundle("/Applications/Foo.app/"))
        XCTAssertTrue(DirectoryWatcher.isInsideAppBundle("/Applications/Foo.app/Contents/"))
    }

    // MARK: - Live FSEvents delivery

    /// End-to-end: an app bundle appearing must actually wake the watcher. Testing the filter
    /// alone would not catch a stream that never starts, or one whose callback misparses the
    /// paths it is handed.
    ///
    /// The bundle is created by a **separate process** on purpose. The stream sets
    /// `kFSEventStreamCreateFlagIgnoreSelf`, so writes from this process are invisible to it by
    /// design — and a real install always comes from Finder, `installd`, or an installer anyway,
    /// which is exactly what spawning `/bin/mkdir` models.
    func testWatcherFiresWhenAnotherProcessInstallsAnAppBundle() throws {
        let fired = expectation(description: "watcher reported a change")
        fired.assertForOverFulfill = false

        let watcher = DirectoryWatcher { fired.fulfill() }
        watcher.start(paths: [tempDir.path])
        defer { watcher.stop() }

        // FSEvents needs a moment to arm before it will report anything.
        Thread.sleep(forTimeInterval: 0.3)

        let mkdir = Process()
        mkdir.executableURL = URL(fileURLWithPath: "/bin/mkdir")
        mkdir.arguments = ["-p", tempDir.appendingPathComponent("Newly Installed.app/Contents").path]
        try mkdir.run()
        mkdir.waitUntilExit()

        wait(for: [fired], timeout: 10)
    }

    /// The watcher must survive being pointed at a symlinked root. FSEvents matches on real
    /// paths and silently delivers nothing for an unresolved one — the failure mode is silence,
    /// not an error, so it needs its own coverage.
    func testWatcherResolvesSymlinkedRoots() throws {
        let realDir = tempDir.appendingPathComponent("real", isDirectory: true)
        let linkDir = tempDir.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkDir, withDestinationURL: realDir)

        let fired = expectation(description: "watcher reported a change through the symlink")
        fired.assertForOverFulfill = false

        let watcher = DirectoryWatcher { fired.fulfill() }
        watcher.start(paths: [linkDir.path])
        defer { watcher.stop() }

        Thread.sleep(forTimeInterval: 0.3)

        let mkdir = Process()
        mkdir.executableURL = URL(fileURLWithPath: "/bin/mkdir")
        mkdir.arguments = ["-p", realDir.appendingPathComponent("Installed.app/Contents").path]
        try mkdir.run()
        mkdir.waitUntilExit()

        wait(for: [fired], timeout: 10)
    }

    func testStartIgnoresPathsThatDoNotExist() {
        let watcher = DirectoryWatcher { XCTFail("Nothing should be reported for a missing path") }
        watcher.start(paths: ["/definitely/not/a/real/directory"])
        watcher.stop()
    }

    func testStopIsIdempotent() {
        let watcher = DirectoryWatcher { }
        watcher.start(paths: [tempDir.path])
        watcher.stop()
        watcher.stop()
    }

    // MARK: - Teardown safety

    /// Regression test for a use-after-free: the FSEvents context hands the callback an
    /// *unretained* pointer to `self`. `FSEventStreamInvalidate` stops any new callback from
    /// being scheduled, but one already dispatched to the watcher's own queue can still be
    /// mid-flight — and a caller (`LibraryScanState.cleanupTimerAndObservers`) nils its reference
    /// to the watcher immediately after `stop()` returns. If `stop()` returned while that
    /// callback was still running, the callback would go on dereferencing a pointer to a
    /// deallocated object.
    ///
    /// This drives the race deliberately: the callback sleeps (simulating slow processing) so it
    /// is still in flight when `stop()` is called, and asserts `stop()` does not return until
    /// that callback has actually finished.
    func testStopBlocksUntilAnInFlightCallbackFinishes() throws {
        let callbackStarted = expectation(description: "callback started")
        let callbackFinished = expectation(description: "callback finished")

        let watcher = DirectoryWatcher {
            callbackStarted.fulfill()
            Thread.sleep(forTimeInterval: 0.3)
            callbackFinished.fulfill()
        }
        watcher.start(paths: [tempDir.path])

        // FSEvents needs a moment to arm before it will report anything.
        Thread.sleep(forTimeInterval: 0.3)

        let mkdir = Process()
        mkdir.executableURL = URL(fileURLWithPath: "/bin/mkdir")
        mkdir.arguments = ["-p", tempDir.appendingPathComponent("Triggers.app/Contents").path]
        try mkdir.run()
        mkdir.waitUntilExit()

        wait(for: [callbackStarted], timeout: 10)

        // The callback is mid-flight (sleeping) on the watcher's own serial queue right now.
        watcher.stop()

        // A zero-timeout wait reports whether the expectation is *already* fulfilled: if
        // `stop()` returned before the callback finished, this is still pending.
        XCTAssertEqual(XCTWaiter().wait(for: [callbackFinished], timeout: 0), .completed,
            "stop() must not return while its callback is still running, or a caller that frees "
            + "the watcher right after stop() returns can deallocate it out from under that callback")
    }
}
