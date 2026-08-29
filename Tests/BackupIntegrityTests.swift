import XCTest
@testable import MacMuster

/// Covers the two defects that made backup export/restore both broken and unsafe:
///
/// - **CRIT-1** — the checksum was computed over JSON that did not yet contain it, then verified
///   against JSON that did, so *every* exported backup failed to restore. The existing
///   `BackupManagerTests` never caught it because they all round-trip `BackupArchive` through
///   `JSONEncoder`/`JSONDecoder` directly, skipping the encode/verify path entirely.
///
/// - **SEC-1** — icon-pack keys came from the untrusted archive and were appended straight onto
///   the cache directory path, so a crafted key wrote anywhere the user could write.
///
/// The round-trip tests here go through `encodeArchive`/`decodeArchive`, which are exactly what
/// `export()` and `restore(from:)` use — the integrity path is covered without an `NSSavePanel`.
@MainActor
final class BackupIntegrityTests: XCTestCase {

    // MARK: - Helpers

    private var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacMuster/icons-v4", isDirectory: true)
    }

    /// A 64-character lowercase hex string, the shape `IconCacheManager` writes.
    private func validIconKey(_ seed: String = "a1b2c3d4") -> String {
        String(repeating: seed, count: 64 / seed.count)
    }

    private func makeArchive(
        hiddenAppPaths: Set<String> = [],
        appFolders: [AppFolder] = [],
        icons: BackupManager.IconPack = BackupManager.IconPack(entries: [:])
    ) -> BackupManager.BackupArchive {
        BackupManager.BackupArchive(
            appFolders: appFolders,
            customOrder: [:],
            hiddenAppPaths: hiddenAppPaths,
            sortOption: ApplicationSorter.SortOption.name.rawValue,
            iconSize: IconSize.medium.rawValue,
            showFoldersFirst: false,
            refreshInterval: 300.0,
            currentFolderId: nil,
            customDirectories: [],
            glowEnabled: false,
            glowColor: "#ffffff",
            glowIntensity: 0.5,
            glowWidth: 2.0,
            fontFamily: "System",
            fontSize: 14.0,
            fontWeight: "Regular",
            pressFeedbackEnabled: true,
            recentAppsEnabled: false,
            overlayOpacity: GlowMetrics.overlayOpacityDefault,
            showInDock: true,
            icons: icons
        )
    }

    // MARK: - CRIT-1: export → restore round trip

    func testEncodedArchiveDecodesSuccessfully() throws {
        // The regression test for CRIT-1. Before the fix this returned nil for every archive.
        let archive = makeArchive(hiddenAppPaths: ["/Applications/Foo.app"])
        let data = try BackupManager.encodeArchive(archive)

        let decoded = BackupManager.decodeArchive(from: data)

        XCTAssertNotNil(decoded, "An archive produced by encodeArchive must decode back — this is the export→restore path")
        XCTAssertEqual(decoded?.hiddenAppPaths, ["/Applications/Foo.app"], "Payload should survive the round trip intact")
        XCTAssertEqual(decoded?.schemaVersion, 2, "Schema version should survive the round trip")
    }

    func testRoundTripSurvivesSetOrderingAcrossManyEntries() throws {
        // `hiddenAppPaths` is a Set, which encodes to a JSON array in iteration order — order that
        // varies between processes. Any integrity scheme that re-encodes the archive to verify it
        // would break on exactly this. Hashing the payload bytes does not, so a large set must
        // round-trip cleanly.
        let paths = Set((0..<200).map { "/Applications/App\($0).app" })
        let data = try BackupManager.encodeArchive(makeArchive(hiddenAppPaths: paths))

        let decoded = BackupManager.decodeArchive(from: data)

        XCTAssertEqual(decoded?.hiddenAppPaths, paths, "A large Set must round-trip regardless of its iteration order")
    }

    func testRoundTripPreservesFolders() throws {
        let folder = AppFolder(name: "Design", appPaths: ["/Applications/Preview.app"])
        let data = try BackupManager.encodeArchive(makeArchive(appFolders: [folder]))

        let decoded = BackupManager.decodeArchive(from: data)

        XCTAssertEqual(decoded?.appFolders.count, 1, "Folders should round-trip")
        XCTAssertEqual(decoded?.appFolders.first?.name, "Design", "Folder name should round-trip")
        XCTAssertEqual(decoded?.appFolders.first?.appPaths, ["/Applications/Preview.app"], "Folder membership should round-trip")
    }

    // MARK: - CRIT-1: corruption is still detected

    func testCorruptedPayloadIsRejected() throws {
        // The checksum has to still do its job: flip a byte inside the payload and the archive
        // must be refused rather than silently restored from damaged data.
        var data = try BackupManager.encodeArchive(makeArchive(hiddenAppPaths: ["/Applications/Foo.app"]))
        guard let file = try? JSONDecoder().decode(BackupManager.BackupFile.self, from: data) else {
            return XCTFail("Encoded data should decode as a BackupFile container")
        }
        var corruptedPayload = file.payload
        corruptedPayload[corruptedPayload.count / 2] ^= 0xFF
        data = try JSONEncoder().encode(
            BackupManager.BackupFile(checksum: file.checksum, payload: corruptedPayload)
        )

        XCTAssertNil(BackupManager.decodeArchive(from: data), "A payload that no longer matches its checksum must be rejected")
    }

    func testTamperedChecksumIsRejected() throws {
        let data = try BackupManager.encodeArchive(makeArchive())
        let file = try JSONDecoder().decode(BackupManager.BackupFile.self, from: data)
        let tampered = try JSONEncoder().encode(
            BackupManager.BackupFile(checksum: String(repeating: "0", count: 64), payload: file.payload)
        )

        XCTAssertNil(BackupManager.decodeArchive(from: tampered), "A checksum that does not match the payload must be rejected")
    }

    func testTruncatedPayloadIsRejected() throws {
        let data = try BackupManager.encodeArchive(makeArchive(hiddenAppPaths: ["/Applications/Foo.app"]))
        let file = try JSONDecoder().decode(BackupManager.BackupFile.self, from: data)
        let truncated = try JSONEncoder().encode(
            BackupManager.BackupFile(checksum: file.checksum, payload: file.payload.dropLast(10))
        )

        XCTAssertNil(BackupManager.decodeArchive(from: truncated), "A truncated payload must be rejected")
    }

    func testGarbageIsRejected() {
        XCTAssertNil(BackupManager.decodeArchive(from: Data("not a backup at all".utf8)), "Non-JSON input must be rejected")
        XCTAssertNil(BackupManager.decodeArchive(from: Data("{}".utf8)), "Empty JSON object must be rejected")
    }

    func testChecksumCoversThePayloadBytes() throws {
        let data = try BackupManager.encodeArchive(makeArchive())
        let file = try JSONDecoder().decode(BackupManager.BackupFile.self, from: data)

        XCTAssertEqual(file.checksum, BackupManager.sha256Hex(file.payload),
            "The stored checksum must be the digest of the payload exactly as written")
        XCTAssertEqual(file.checksum.count, 64, "SHA256 hex digest should be 64 characters")
    }

    func testLegacyFlatArchiveStillDecodes() throws {
        // Archives written before the BackupFile container existed are a bare BackupArchive.
        // They carry no usable checksum (the old scheme never produced a verifiable one), so
        // they are accepted unverified rather than rejected.
        let legacy = try JSONEncoder().encode(makeArchive(hiddenAppPaths: ["/Applications/Legacy.app"]))

        let decoded = BackupManager.decodeArchive(from: legacy)

        XCTAssertNotNil(decoded, "A pre-container archive should still decode")
        XCTAssertEqual(decoded?.hiddenAppPaths, ["/Applications/Legacy.app"], "Legacy archive contents should be preserved")
    }

    // MARK: - SEC-1: icon cache key validation

    func testIconCacheKeyValidationAcceptsRealCacheKeys() {
        // Cross-check against the real generator rather than a hand-written constant, so the
        // validator can never drift away from the format the cache actually writes.
        for appearance in IconAppearance.allCases {
            let key = IconCacheManager.shared.cacheKey(for: "/Applications/Safari.app", appearance: appearance)
            XCTAssertTrue(BackupManager.isValidIconCacheKey(key),
                "A key produced by IconCacheManager.cacheKey must be accepted (appearance: \(appearance))")
        }
    }

    func testIconCacheKeyValidationRejectsTraversalAndMalformedKeys() {
        let rejected: [(String, String)] = [
            ("../../../../evil.txt", "parent-directory traversal"),
            ("../../LaunchAgents/x.plist", "traversal into LaunchAgents"),
            ("/etc/passwd", "absolute path"),
            ("subdir/" + String(repeating: "a", count: 56), "embedded path separator"),
            ("", "empty key"),
            (String(repeating: "a", count: 63), "too short"),
            (String(repeating: "a", count: 65), "too long"),
            (String(repeating: "A", count: 64), "uppercase hex"),
            (String(repeating: "g", count: 64), "non-hex letters"),
            (String(repeating: "٣", count: 64), "non-ASCII digits"),
            (String(repeating: "a", count: 60) + ".met", "wrong shape with extension"),
        ]

        for (key, reason) in rejected {
            XCTAssertFalse(BackupManager.isValidIconCacheKey(key), "Key should be rejected — \(reason): \(key)")
        }
    }

    // MARK: - SEC-1: restore must not write outside the cache directory

    func testRestoreIgnoresTraversalKeysAndWritesNothingOutsideCache() throws {
        // The end-to-end proof for SEC-1: drive a hostile archive through the real restore path
        // and assert nothing lands outside the cache directory.
        let escapeTargets = [
            cacheDir.appendingPathComponent("../../../macmuster-sec1-escape.txt"),
            cacheDir.appendingPathComponent("../macmuster-sec1-escape.txt"),
        ]
        for target in escapeTargets {
            try? FileManager.default.removeItem(at: target.standardizedFileURL)
        }
        defer {
            for target in escapeTargets {
                try? FileManager.default.removeItem(at: target.standardizedFileURL)
            }
        }

        let goodKey = validIconKey()
        let hostileIcons = BackupManager.IconPack(entries: [
            "../../../macmuster-sec1-escape.txt": Data("pwned".utf8),
            "../macmuster-sec1-escape.txt": Data("pwned".utf8),
            goodKey: Data([0xAB, 0xCD]),
        ])
        let preview = BackupManager.BackupPreview(
            archive: makeArchive(icons: hostileIcons),
            validAppPaths: [],
            missingAppPaths: []
        )

        BackupManager.shared.apply(preview: preview)

        for target in escapeTargets {
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.standardizedFileURL.path),
                "Restore must not write outside the cache directory: \(target.standardizedFileURL.path)")
        }

        // The legitimate entry alongside the hostile ones must still be restored — rejecting bad
        // keys must not turn into rejecting the whole icon pack.
        let restored = cacheDir.appendingPathComponent(goodKey)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restored.path),
            "A valid icon key should still be restored when hostile keys are present")
        XCTAssertEqual(try? Data(contentsOf: restored), Data([0xAB, 0xCD]), "Valid icon data should be written intact")
        try? FileManager.default.removeItem(at: restored)
    }

    func testHostileKeysSurviveTheFullEncodeDecodeRestorePath() throws {
        // Belt and braces: the hostile key must be refused even when it arrives the way a real
        // attack would — inside a well-formed, correctly-checksummed archive file.
        let escape = cacheDir.appendingPathComponent("../../../macmuster-sec1-roundtrip.txt").standardizedFileURL
        try? FileManager.default.removeItem(at: escape)
        defer { try? FileManager.default.removeItem(at: escape) }

        let archive = makeArchive(icons: BackupManager.IconPack(entries: [
            "../../../macmuster-sec1-roundtrip.txt": Data("pwned".utf8)
        ]))
        let data = try BackupManager.encodeArchive(archive)

        guard let decoded = BackupManager.decodeArchive(from: data) else {
            return XCTFail("A well-formed hostile archive should still decode — it is rejected at write time, not parse time")
        }
        BackupManager.shared.apply(
            preview: BackupManager.BackupPreview(archive: decoded, validAppPaths: [], missingAppPaths: [])
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: escape.path),
            "A checksummed archive carrying a traversal key must still write nothing outside the cache directory")
    }
}
