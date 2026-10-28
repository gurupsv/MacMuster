import XCTest
@testable import MacMuster

@MainActor
final class AppDragItemTests: XCTestCase {

    func testAppBundleOffersFileURL() {
        let item = AppDragItem(path: "/System/Applications/Calculator.app", isFolder: false)
        XCTAssertTrue(item.offersFileURL)
        XCTAssertEqual(item.fileURL.path, "/System/Applications/Calculator.app")
    }

    func testFolderTileDoesNotOfferFileURL() {
        let item = AppDragItem(path: "5C1B7E2A-0000-0000-0000-000000000000", isFolder: true)
        XCTAssertFalse(item.offersFileURL)
    }

    func testFolderFlagWinsOverAppSuffix() {
        XCTAssertFalse(AppDragItem(path: "/x/Thing.app", isFolder: true).offersFileURL)
    }

    func testNonAppPathDoesNotOfferFileURL() {
        XCTAssertFalse(AppDragItem(path: "/tmp/notes.txt", isFolder: false).offersFileURL)
    }
}
