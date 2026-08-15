import XCTest
@testable import MacMuster

/// `RefreshReason` exists to keep "always scan" and "rebuild icons" as separate decisions. The
/// filesystem watcher needs the first without the second, which the old single `force` flag
/// could not express.
final class RefreshReasonTests: XCTestCase {

    typealias Reason = LibraryScanState.RefreshReason

    func testScheduledIsTheOnlyReasonThatHonorsTheStalenessGuard() {
        XCTAssertFalse(Reason.scheduled.bypassesStalenessCheck,
            "The periodic timer must be able to skip a scan, or it is not cheap")
        XCTAssertTrue(Reason.fileSystemEvent.bypassesStalenessCheck,
            "An install into an existing subdirectory moves no watched mtime — the guard would skip it")
        XCTAssertTrue(Reason.userRequested.bypassesStalenessCheck,
            "Pressing Refresh Now must always scan")
    }

    func testOnlyAnExplicitUserRequestRebuildsIcons() {
        XCTAssertTrue(Reason.userRequested.rebuildsIcons,
            "Refresh Now exists to re-decode icons that are rendering wrong")
        XCTAssertFalse(Reason.fileSystemEvent.rebuildsIcons,
            "Installing an app invalidates no existing icon — rebuilding them all would be wasteful")
        XCTAssertFalse(Reason.scheduled.rebuildsIcons,
            "The background refresh must stay incremental")
    }
}
