import XCTest
@testable import MacMuster

/// Guards the integrity of the offline classification data in `SmartFolderCatalog`. The wizard's
/// correctness rests on this table being internally consistent, so these tests fail loudly on a
/// duplicate, a malformed key, a dead category, or a localized name that never made it into
/// `Localizable.xcstrings`.
///
/// The localization checks deliberately parse the `.xcstrings` file rather than calling
/// `String(localized:)`: under `swift test` the main bundle does not carry the SPM-processed
/// resources, so `String(localized:)` always returns the key itself — a "non-empty" assertion
/// against it would pass even for a missing entry and prove nothing.
final class SmartFolderCatalogTests: XCTestCase {

    // MARK: - Fixtures

    private struct XCStrings: Decodable {
        let strings: [String: [String: String]]
    }

    /// The checked-in string catalog, located from this source file so the suite is portable.
    private var xcstringsURL: URL {
        URL(fileURLWithPath: #filePath)              // .../Tests/SmartFolderCatalogTests.swift
            .deletingLastPathComponent()              // .../Tests
            .deletingLastPathComponent()              // repo root
            .appendingPathComponent("Sources/MacMuster/Resources/Localizable.xcstrings")
    }

    private func catalogStringKeys() throws -> Set<String> {
        let data = try Data(contentsOf: xcstringsURL)
        return Set(try JSONDecoder().decode(XCStrings.self, from: data).strings.keys)
    }

    // MARK: - Localization

    func testEveryCategoryDisplayNameExistsInStringCatalog() throws {
        let keys = try catalogStringKeys()
        for category in SmartFolderCategory.allCases {
            // In the test process this returns the key (the main bundle has no resources), so the
            // assertion is really "is this key present in the catalog".
            let name = category.displayName
            XCTAssertTrue(keys.contains(name),
                "SmartFolderCategory.\(category) display name \(name) is missing from Localizable.xcstrings")
        }
    }

    func testCategoryDisplayNamesAreUnique() {
        let names = Set(SmartFolderCategory.allCases.map(\.displayName))
        XCTAssertEqual(names.count, SmartFolderCategory.allCases.count,
            "Two smart-folder categories must not share a display name")
    }

    // MARK: - Coverage

    func testEveryCategoryHasAtLeastOneTier() {
        let covered: Set<SmartFolderCategory> =
            Set(SmartFolderCategory.byBundleID.values)
            .union(SmartFolderCategory.vendorPrefixes.values)
            .union(SmartFolderCategory.byCategoryUTI.values)
            .union(SmartFolderCategory.byName.values)
        for category in SmartFolderCategory.allCases {
            XCTAssertTrue(covered.contains(category),
                "SmartFolderCategory.\(category) has no override, prefix, UTI, or name entry — it can never be assigned to")
        }
    }

    // MARK: - Key well-formedness

    func testCategoryUTIsAreWellFormed() {
        let pattern = #"^public\.app-category\.[a-z][a-z-]*$"#
        for key in SmartFolderCategory.byCategoryUTI.keys {
            XCTAssertNotNil(key.range(of: pattern, options: .regularExpression),
                "UTI \(key) is not a well-formed public.app-category.* identifier")
        }
    }

    func testBundleIDOverridesAreWellFormed() {
        // Bundle identifiers are case-sensitive (e.g. com.apple.Safari, org.mozilla.firefox), so
        // the check is "is a valid reverse-DNS identifier", not "is lowercase".
        let pattern = #"^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)+$"#
        for key in SmartFolderCategory.byBundleID.keys {
            XCTAssertNotNil(key.range(of: pattern, options: .regularExpression),
                "Bundle ID \(key) is not a well-formed reverse-DNS identifier")
        }
    }

    func testNameAliasesAreNormalized() {
        for key in SmartFolderCategory.byName.keys {
            let normalized = key.trimmingCharacters(in: .whitespaces).lowercased()
            XCTAssertEqual(key, normalized, "Name alias \(key) must be stored in normalized (lowercase, trimmed) form")
        }
    }

    func testBundleIDOverridesAreUniqueIgnoringCase() {
        // Bundle-ID matching is case-insensitive, so two keys that differ only by case are a real
        // collision even though the compiler (which only *warns* on literal duplicates) would let
        // them through. Guard against that here.
        let lowercased = Set(SmartFolderCategory.byBundleID.keys.map { $0.lowercased() })
        XCTAssertEqual(lowercased.count, SmartFolderCategory.byBundleID.count,
            "Two bundle ID overrides differ only by case")
    }

    // MARK: - Cross-tier consistency

    func testBundleIDOverridesDoNotConflictWithVendorPrefixes() {
        for (bundleID, category) in SmartFolderCategory.byBundleID {
            for (prefix, prefixCategory) in SmartFolderCategory.vendorPrefixes where bundleID.hasPrefix(prefix) {
                XCTAssertEqual(category, prefixCategory,
                    "Bundle ID \(bundleID) is overridden to \(category) but vendor prefix \(prefix) implies \(prefixCategory)")
            }
        }
    }

    // MARK: - sanitizedFolders (untrusted input guard)

    func testSanitizedFoldersKeepsAValidKey() {
        let folder = AppFolder(name: "Development", appPaths: [], smartCategoryKey: "development")
        XCTAssertEqual(SmartFolderCategory.sanitizedFolders([folder])[0].smartCategoryKey, "development")
    }

    func testSanitizedFoldersDropsAnUnknownKeyButKeepsTheFolder() {
        let folder = AppFolder(name: "Weird", appPaths: ["/Applications/A.app"], smartCategoryKey: "not-a-real-category")
        let cleaned = SmartFolderCategory.sanitizedFolders([folder])[0]
        XCTAssertNil(cleaned.smartCategoryKey, "An unknown key must be dropped")
        XCTAssertEqual(cleaned.name, "Weird")
        XCTAssertEqual(cleaned.appPaths, ["/Applications/A.app"], "The folder itself must be kept")
    }

    func testSanitizedFoldersDropsAnEmptyKey() {
        let folder = AppFolder(name: "Empty", appPaths: [], smartCategoryKey: "")
        XCTAssertNil(SmartFolderCategory.sanitizedFolders([folder])[0].smartCategoryKey)
    }

    func testSanitizedFoldersLeavesNilKeysAndOtherFieldsAlone() {
        let folder = AppFolder(id: "6F1A2B3C-0000-4000-8000-0000000000AA", name: "Tools", appPaths: ["/Applications/A.app"],
                               customIcon: "icon", smartCategoryKey: nil)
        let cleaned = SmartFolderCategory.sanitizedFolders([folder])[0]
        XCTAssertNil(cleaned.smartCategoryKey)
        XCTAssertEqual(cleaned.id, "6F1A2B3C-0000-4000-8000-0000000000AA")
        XCTAssertEqual(cleaned.name, "Tools")
        XCTAssertEqual(cleaned.appPaths, ["/Applications/A.app"])
        XCTAssertEqual(cleaned.customIcon, "icon")
    }

    // MARK: - Folder id guard (SEC-9)

    func testSanitizedFoldersRekeysIdThatCollidesWithAnAppPath() {
        let folder = AppFolder(id: "/Applications/Safari.app", name: "F", appPaths: [])
        let cleaned = SmartFolderCategory.sanitizedFolders([folder])[0]
        XCTAssertNotEqual(cleaned.id, "/Applications/Safari.app")
        XCTAssertNotNil(UUID(uuidString: cleaned.id))
    }

    func testSanitizedFoldersRekeysDuplicateIdsButKeepsTheFirst() {
        let id = UUID().uuidString
        let result = SmartFolderCategory.sanitizedFolders([
            AppFolder(id: id, name: "A", appPaths: []), AppFolder(id: id, name: "B", appPaths: []),
            AppFolder(id: id, name: "C", appPaths: [])])
        XCTAssertEqual(result[0].id, id)
        XCTAssertEqual(Set(result.map(\.id)).count, 3, "every folder needs a distinct id")
        XCTAssertEqual(result.map(\.name), ["A", "B", "C"])
    }

    func testSanitizedFoldersLeavesValidUniqueIdsAndIsStableAcrossCalls() {
        let ok = AppFolder(name: "ok", appPaths: [])
        XCTAssertEqual(SmartFolderCategory.sanitizedFolders([ok])[0].id, ok.id)
        let bad = AppFolder(id: "not-a-uuid", name: "bad", appPaths: [])
        XCTAssertEqual(SmartFolderCategory.sanitizedFolders([bad])[0].id,
                       SmartFolderCategory.sanitizedFolders([bad])[0].id,
                       "re-keying must be deterministic so a reload does not change ids")
    }
}
