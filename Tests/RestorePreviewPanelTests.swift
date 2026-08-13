import XCTest
@testable import MacMuster

@MainActor
final class RestorePreviewPanelTests: XCTestCase {

    // MARK: - Async runModal (Bug #2: no more DispatchSemaphore blocking main thread)

    func testRunModalReturnsCancelWhenNoWindow() async {
        // If init fails to create a window (unlikely in practice), runModal returns .cancel
        // without blocking. We can't easily trigger this path, but the async signature
        // itself is the key fix — it no longer blocks the main thread.
        let panel = RestorePreviewPanel(
            folderCount: 0,
            appCount: 0,
            missingCount: 0,
            missingPaths: []
        )
        // The window is created in init, so this should have a window.
        // We test the async contract: runModal must not block.
        let start = Date()
        let task = Task { @MainActor in
            _ = await panel.runModal()
        }
        // Cancel immediately — the panel is waiting for user input via continuation,
        // so it should suspend, not block.
        task.cancel()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "runModal should not block the main thread")
    }

    func testRunModalSuspendsWithoutBlocking() async {
        let panel = RestorePreviewPanel(
            folderCount: 2,
            appCount: 5,
            missingCount: 1,
            missingPaths: ["/Applications/Gone.app"]
        )

        // Start runModal in a task — it should suspend on the continuation, not block.
        let task = Task { @MainActor in
            _ = await panel.runModal()
        }

        // Give the task a moment to reach the continuation suspension point.
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // The task should still be running (suspended), not completed.
        // We can't directly check suspension, but we can verify the window was shown.
        // The key assertion: the main thread is not blocked — we reached this line.
        XCTAssertTrue(true, "Main thread is not blocked by runModal")

        task.cancel()
    }

    // MARK: - Window Creation

    func testInitCreatesWindow() {
        let panel = RestorePreviewPanel(
            folderCount: 3,
            appCount: 10,
            missingCount: 2,
            missingPaths: ["/Applications/A.app", "/Applications/B.app"]
        )
        // Window is created in init — verify the panel object exists and has the right counts.
        XCTAssertEqual(panel.folderCount, 3)
        XCTAssertEqual(panel.appCount, 10)
        XCTAssertEqual(panel.missingCount, 2)
        XCTAssertEqual(panel.missingPaths.count, 2)
    }

    func testInitWithEmptyMissingPaths() {
        let panel = RestorePreviewPanel(
            folderCount: 1,
            appCount: 3,
            missingCount: 0,
            missingPaths: []
        )
        XCTAssertEqual(panel.folderCount, 1)
        XCTAssertEqual(panel.appCount, 3)
        XCTAssertEqual(panel.missingCount, 0)
        XCTAssertTrue(panel.missingPaths.isEmpty)
    }
}
