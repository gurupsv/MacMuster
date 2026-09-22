import XCTest
@testable import MacMuster

@MainActor
final class LaunchieImporterTests: XCTestCase {

    override func setUp() async throws {
        clearDefaults()
    }

    override func tearDown() async throws {
        clearDefaults()
    }

    private nonisolated func clearDefaults() {
        for key in ["appFolders", "hiddenAppPaths", "customOrder", "currentFolderId",
                    "sortOption", "refreshInterval", "columnCount", "customDirectories"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func writeFixture(_ json: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try? json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Parsing

    func testParseReturnsNilForUnrelatedJSON() {
        let url = writeFixture(#"{"hello": "world"}"#)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNil(LaunchieImporter.shared.parse(from: url), "Non-Launchie JSON should not parse as a Launchie export")
    }

    func testParseReturnsNilForMacMusterBackup() {
        // MacMuster's own backup shape doesn't have Launchie's `folders.folders` / `layout.positions`
        // nesting, so it should fail to decode as a Launchie archive.
        let url = writeFixture(#"{"schemaVersion": 2, "appFolders": []}"#)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNil(LaunchieImporter.shared.parse(from: url))
    }

    func testParseExtractsFoldersAndValidatesAppPaths() {
        // /Applications/Safari.app exists on every macOS install; the bogus path does not.
        let json = #"""
        {
          "folders": {
            "folders": [
              {
                "id": "1B69AF25-A04F-4BEE-A88A-FCA5F163C5B0",
                "name": "Browsers",
                "apps": ["/Applications/Safari.app", "/Applications/DoesNotExist.app"],
                "position": 0,
                "sortMode": "Custom",
                "allowEmptySpaces": true
              }
            ]
          },
          "layout": { "positions": {} },
          "schemaVersion": 1,
          "settings": {}
        }
        """#
        let url = writeFixture(json)
        defer { try? FileManager.default.removeItem(at: url) }

        guard let preview = LaunchieImporter.shared.parse(from: url) else {
            return XCTFail("Expected a valid Launchie export to parse")
        }

        XCTAssertEqual(preview.folderCount, 1)
        XCTAssertEqual(preview.folders.first?.id, "1B69AF25-A04F-4BEE-A88A-FCA5F163C5B0")
        XCTAssertEqual(preview.folders.first?.name, "Browsers")
        XCTAssertEqual(preview.folders.first?.appPaths, ["/Applications/Safari.app"],
            "The non-existent app should be dropped from the folder's membership")
        XCTAssertEqual(preview.missingPaths, ["/Applications/DoesNotExist.app"])
        XCTAssertEqual(preview.appCount, 1)
    }

    func testParseMapsFolderPositionPrefixToBareFolderID() {
        let json = #"""
        {
          "folders": {
            "folders": [
              { "id": "F1", "name": "Games", "apps": [] }
            ]
          },
          "layout": {
            "positions": {
              "/Applications/Safari.app": 3,
              "folder:F1": 0
            }
          }
        }
        """#
        let url = writeFixture(json)
        defer { try? FileManager.default.removeItem(at: url) }

        guard let preview = LaunchieImporter.shared.parse(from: url) else {
            return XCTFail("Expected a valid Launchie export to parse")
        }

        // "folder:F1" becomes the bare folder id — MacMuster's customOrder keys a folder's
        // position by its raw UUID, since a folder's synthetic Application.path *is* its id.
        XCTAssertEqual(preview.customOrder["F1"], 0)
        XCTAssertNil(preview.customOrder["folder:F1"])
        XCTAssertEqual(preview.customOrder["/Applications/Safari.app"], 3)
    }

    func testParseDropsPositionEntriesForUnknownFolderOrMissingApp() {
        let json = #"""
        {
          "folders": { "folders": [] },
          "layout": {
            "positions": {
              "folder:UnknownID": 0,
              "/Applications/DoesNotExist.app": 1
            }
          }
        }
        """#
        let url = writeFixture(json)
        defer { try? FileManager.default.removeItem(at: url) }

        guard let preview = LaunchieImporter.shared.parse(from: url) else {
            return XCTFail("Expected a valid Launchie export to parse")
        }

        XCTAssertTrue(preview.customOrder.isEmpty,
            "Positions referencing an undefined folder or a missing app should be dropped")
    }

    // MARK: - Apply

    func testApplyWritesFoldersAndCustomOrderToLiveStores() {
        let folder = AppFolder(id: "F1", name: "Browsers", appPaths: ["/Applications/Safari.app"])
        let preview = LaunchieImporter.ImportPreview(
            folders: [folder],
            customOrder: ["/Applications/Safari.app": 0, "F1": 1],
            folderCount: 1,
            appCount: 1,
            missingPaths: []
        )

        LaunchieImporter.shared.apply(preview: preview)

        XCTAssertEqual(FolderStore.shared.folders.map(\.id), ["F1"])
        XCTAssertEqual(PreferencesStore.shared.loadCustomOrder()?["F1"], 1)
        XCTAssertEqual(PreferencesStore.shared.loadCustomOrder()?["/Applications/Safari.app"], 0)

        FolderStore.shared.folders = []
    }
}
