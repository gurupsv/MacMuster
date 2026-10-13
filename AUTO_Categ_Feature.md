# Smart Folders Wizard — Implementation Plan

## As-is → to-be

**Today:** folders are created manually (`LibraryScanState.createFolder`), membership changes one app at a time, no automatic classification exists (`getCategory` is only a `/System` prefix test, `LibraryScanState+Display.swift:9`), and `Application` carries **no bundle identifier** (scanner derives name from filename only, `ApplicationScanner.swift:55`).

**To-be:** an on-demand, modal, multi-step wizard that (1) creates a user-chosen subset of predefined folders, (2) classifies installed apps **offline** (Info.plist category + bundled override catalog; data never leaves the Mac), (3) applies everything in one batch mutation, re-validated against live state, (4) offers one-step Undo, (5) optionally plays a gated recap animation, and (6) is idempotently rerunnable — only apps in *no* folder are candidates, existing membership is never touched.

---

## Decided product answers

| Question | Decision |
|---|---|
| Predefined folders | 9: Productivity, Development, Design & Creativity, **Internet & Communication**, Media & Entertainment, **Tools**, Games, Finance, Education & Reference. ("Tools", not "Utilities", to avoid confusion with `AppCategory.utilities`.) |
| Memberships per app | **One folder per app**, first-match-wins. |
| System apps | Apps where `getCategory(for:) == .system` are skipped. `com.apple.*` apps in `/Applications` (Safari, Xcode, …) **are** classified. |
| Rerun | Assigns to existing wizard folders only; opt-in checkbox "Also create missing folders" (default **off**). |
| Empty folders | Never created — a folder is created only if ≥ 1 app is assigned to it (root view hides empty folders, `LibraryScanState+Display.swift:89`, so they would be invisible clutter). |
| Undo | Offered on the summary step. |
| Animation | Gated on reduce motion, Low-GPU Glass (`simpleGlass`), Low Power Mode, and an app-count cap. No CPU-count test. |
| Onboarding offer | Deferred. |
| Remembering apps the user pulls out of a wizard folder | Deferred (would need a persisted-format change). Known limitation: a rerun re-suggests them; the review step lets the user uncheck. |

---

## Core design decisions

### D1. Override catalog as Swift source

Verified: `build_common.sh` copies only its `BUNDLE_RESOURCES` allowlist; the SPM resource bundle never reaches the `.app`, so a JSON resource would require an ask-first build-script edit plus a dual loader. Use a generated `SmartFolderCatalog.swift` (`GENERATED` header) instead.

- Explicit type annotation on the literal (`static let byBundleID: [String: SmartFolderCategory] = [...]`) to keep type-checking fast.
- Because of D2 tier 2, the catalog is **overrides + gap-fillers** (target ~200–400 entries), not a 1,500-entry master list.
- Optional `vendorPrefixes: [String: SmartFolderCategory]` (e.g. `"com.jetbrains."` → `.development`), only for vendors whose apps all belong in one category.
- No generator script (would be ask-first); the file is hand-maintained.

### D2. Classification: one capped Info.plist read per app, only when the wizard runs

New `nonisolated BundleInfoReader` reads `CFBundleIdentifier` **and** `LSApplicationCategoryType` from `Contents/Info.plist` (`PropertyListSerialization`, size-capped read, `try?`, inside `Task.detached`). Never on the scan path. Values in, values out.

Matching order per app, first hit wins:

1. Bundle ID exact hit in catalog (override).
2. Bundle ID matches a catalog `vendorPrefixes` entry.
3. `LSApplicationCategoryType` mapped via a fixed table of the `public.app-category.*` UTIs → folder category (table lives in `SmartFolderCatalog.swift`; unknown UTI → no match).
4. **Exact** normalized name (case/diacritic-insensitive, trimmed) against catalog name aliases. No prefix matching.
5. No match → app stays loose.

Results sorted by `ApplicationSorter.isOrderedBefore` with path tiebreak for determinism.

### D3. Stable folder identity: `AppFolder.smartCategoryKey: String?`

- Optional field; `AppFolder.init` gains `smartCategoryKey: String? = nil`, so `FolderStore.createFolder` and `LaunchieImporter.swift:74` compile unchanged. Synthesized Codable decodes old UserDefaults data and backups without the key.
- Rerun matches existing folders by key first, then by exact folder name.
- When a folder is reused by name (no key), the wizard **stamps the key** onto it in the same batch, so later renames still match.
- **Untrusted input:** on restore (backup or Launchie import) and on load from UserDefaults, a `smartCategoryKey` that isn't a known `SmartFolderCategory` raw value is dropped (set to nil); the folder itself is kept. One shared pure sanitizer, `nonisolated static func SmartFolderCategory.sanitizedFolders(_ folders: [AppFolder]) -> [AppFolder]` (in `SmartFolderCatalog.swift`), called from **both** call sites: `BackupManager.apply` (`BackupManager.swift:376`, covers backup and Launchie restores) and `PreferencesStore.loadFolders` (`PreferencesStore.swift:275`, covers UserDefaults). Tests: the sanitizer directly (known key kept, unknown/empty/garbage → nil, other fields untouched) plus one restore round-trip and one UserDefaults round-trip with a garbage key.
- The key is never user-visible. Display names via `String(localized:)` + `Localizable.xcstrings`.
- **Ask-first gate (persisted format): requires explicit owner approval before phase 3.**

### D3b. Backup version stamp and restore compatibility gate — **separate change**

The wizard does not depend on this: `smartCategoryKey` is optional and older readers ignore it. D3b ships as its own branch/PR (phase B below) so the wizard is not blocked on it, and vice versa.

**Version source:** `Bundle.main.infoDictionary["CFBundleShortVersionString"]` (same source as `SettingsContentView.swift:14`; written by `create_app_bundle.sh:59` from `version.txt`). It is nil under `swift run` and `swift test`, so the fields are set where `export()` constructs `BackupArchive` (`BackupManager.swift:250`), with values from a small pure helper: `nonisolated static func versionStamp(appVersion: String?) -> (createdBy: String?, minimum: String)`. `export()` passes `Bundle.main`'s value. Tests call the helper with an injected version, build a `BackupArchive` with its output, and round-trip it through the existing `encodeArchive(_:)` (`:308`) and `decodeArchive(from:)`. No new export method; `export()` keeps its signature and save-panel flow. Without injection, "export writes both fields" cannot pass.

**Compatibility matrix**

| Reader ↓ / Data → | Old data (no key, no version stamp) | New data (key + version stamp) |
|---|---|---|
| 1.0.4 and older | as today | Restores; unknown fields are ignored (synthesized `Decodable`), so keys are dropped. Reruns fall back to name matching. These builds **cannot** enforce a minimum version. |
| 1.0.5+ | Decodes; `smartCategoryKey` = nil; missing stamp = "unknown, compatible" | Full support plus the version gate below |

**New optional fields in `BackupArchive`** (inside the checksummed payload, so they are tamper-evident):

- `createdByAppVersion: String?` — `CFBundleShortVersionString` of the app that wrote the backup (from `version.txt` via the bundle Info.plist). Shown in the restore preview.
- `minimumAppVersion: String?` — the oldest app version that can restore this backup **correctly**. Raised only when a release adds data an older reader would mis-apply. Silently dropping an optional field doesn't count. Defined as a constant (`BackupCompatibility.minimumReaderVersion` in `Constants.swift`, with a rationale comment per bump). For 1.0.5 it is `"1.0.5"`.

**Restore flow (1.0.5+)**

1. Verify the checksum, as today.
2. Decode a tiny `BackupVersionHeader` (just the two optional fields) from the payload **before** the full archive. A backup whose full schema this build doesn't understand can still report "needs version X" instead of "corrupted".
3. Gate via a pure `nonisolated static func compatibility(current:minimum:createdBy:) -> BackupCompatibility`:
   - `minimumAppVersion > current` → **refuse**, with the alert "This backup requires MacMuster X or later. You have Y." Nothing is applied.
   - `createdByAppVersion > current` but minimum satisfied → allowed; the preview shows "Created by a newer version; some settings may be skipped."
   - Missing fields (old backups) → compatible.
   - Current version unknown (`swift run`/tests have no bundle Info.plist) → skip the gate (fail soft).
4. Also refuse `schemaVersion > 2` (the highest this build understands). This is a read-side check only; no schema bump.
5. `decodeArchive` returns a result enum (`.ok(archive)`, `.corrupted`, `.requiresNewerApp(minimum:)`, `.unsupportedSchema`) instead of `Optional`, so `StatusBarManager` shows the right message.

**Version comparison**: numeric, component-wise on dot-separated integers (`1.0.10 > 1.0.9`); missing components count as 0; anything unparseable → treat as compatible and show the raw string. No string comparison.

`currentSchemaVersion` (`PreferencesStore`) and `BackupArchive.schemaVersion` stay unchanged: every addition is optional.

### D4. Wizard UI: imperative panel modeled on `RestorePreviewPanel`

`SmartFoldersWizardPanel` (`NSWindow` + `NSHostingView` + async `runModal()` continuation, `level = .floating`, `NSApp.activate`, `windowWillClose → cancel`, double-resume-safe `complete`). Steps: choose folders → review (per-app checkboxes, grouped by folder) → apply → summary (counts + Undo + optional animation).

Entry points: `StatusBarManager` menu item "Smart Folders Wizard…" beside Export/Restore Backup, and a "Run Smart Folders Wizard" button in `FoldersSettingsPanel` (`SettingsContentView.swift:676`). A second invocation while open brings the existing panel to front.

### D5. Apply in ONE batch, re-validated at apply time

The wizard does not block the app, so a rescan, a drag into a folder, a hide, or a folder deletion can happen while the review step is open. `LibraryScanState.applySmartFolderBatch(plan:) -> SmartFolderUndoToken?`:

1. **Re-validate** against current state, using the same eligibility predicate as D7 (`LibraryScanState.isSmartFolderCandidate(_:)`, main actor): drop entries with `isFolder == true` or a path without the `.app` suffix, paths now in any folder, now in `hiddenAppPaths`/permanently hidden, now `.system`, or absent from `appPathIndex`. This matters because the batch writes `AppFolder.appPaths` directly and so bypasses `FolderStore.addAppToFolder`'s `.app` guard (`FolderStore.swift:36`). Re-resolve each target folder by key, then name; if missing, create it only if the "create missing" option was on (or it's a first-run selection) **and** it still has ≥ 1 app — otherwise drop those assignments.
2. Build `var newFolders = folders` locally: append memberships, stamp keys (D3), set `modifiedAt` only on changed folders, append new folders.
3. **If nothing changed, return `nil` here** — before any state is touched: no folder close, no bump, no persist. This holds whether or not a folder is open.
4. `if currentFolderId != nil { closeFolder() }`. `closeFolder()` itself bumps `dataVersion` (via the `currentFolderId` `didSet`, `LibraryScanState.swift:65`), persists `currentFolderId`, and rebuilds the index. That bump is kept: it is an existing path and reusing it unchanged beats special-casing it. A bare `currentFolderId = nil` would bump just the same, since the `didSet` always runs. Re-validation and folder resolution in steps 1–2 don't depend on `currentFolderId`, so closing after them is safe.
5. `folders = newFolders` — **single assignment**; its `didSet` already pushes to `FolderStore` (`LibraryScanState.swift:62`), giving exactly one persist. Do **not** also assign `FolderStore.shared.folders`.
6. `dataVersion += 1` once for the membership change (folder `didSet` does not bump), then `cachedDisplayedApps = nil`, `rebuildAppPathIndex()`, `updateFilteredApps()`, `regenerateFolderIcons(changedAppPaths: <assigned paths>)`. The index rebuild repeats the one inside `closeFolder()` in the open-folder path, which is redundant but harmless.

**Bump accounting per call:** no-op → 0 (folder open or not); applied with no folder open → 1; applied with a folder open → 2 (close + apply).

Lives in `LibraryScanState.swift` (needs `private` `rebuildAppPathIndex`/`regenerateFolderIcons`).

### D5b. Undo

The undo token holds the pre-apply `folders` snapshot plus the exact changes (added paths per folder id, created folder ids, stamped keys). `undoSmartFolderBatch(_:)`:

- "Unchanged since apply" is an **explicit content comparison**, not `==`: `AppFolder`'s `==`/`hash` are hand-written and compare `id` only (`Types.swift:208-214`), so `folders == snapshot` would be true after membership changes. Add `AppFolder.hasSameContent(as:)` comparing `id`, `name`, `appPaths` (ordered), `customIcon`, `smartCategoryKey`, `modifiedAt`; arrays are equal when counts match and every pair matches in order. The token stores the post-apply `folders` for this comparison.
- If unchanged → restore the snapshot in one assignment.
- Otherwise → remove only the added paths, delete created folders that are now empty, clear keys it stamped; one assignment.
- Compute the reverted `folders` first; if it equals the current content (nothing left to undo), return without touching state (0 bumps).
- If the open folder (`currentFolderId`) is one undo deletes, call `closeFolder()` before assigning. Bump counts mirror D5: 1, or 2 when that close happens.
- Same refresh sequence as D5 step 6, with `regenerateFolderIcons(changedAppPaths:)` given the paths **removed** by undo, so affected folder composites refresh. Token is discarded when the panel closes.

### D6. Animation: in-wizard recap, cosmetic, gated

Runs only after apply succeeded. App-icon chips (from `iconSlot(for:)` — every indexed path has a slot, filled by `rebuildAppPathIndex`) fly into folder tiles with staggered springs. Plays only when **all** hold:

- `accessibilityReduceMotion` is off,
- `settings.simpleGlass` (Low-GPU Glass) is off,
- `ProcessInfo.processInfo.isLowPowerModeEnabled` is false,
- assigned-app count ≤ `WizardMetrics.maxAnimatedApps` (200).

Plus a user checkbox "Show animation" (default on). Constants in `WizardMetrics`.

### D7. Candidates and rerun contract

Candidates = `displayOrder` minus entries with `isFolder == true` (scanner-made wrapper-folder tiles such as "Microsoft Office", which `ApplicationScanner.swift:89-102` inserts into `displayOrder` and `rebuildAppPathIndex` indexes) and minus any path without the `.app` suffix, minus `permanentlyHiddenAppPaths`, minus `hiddenAppPaths` (always — independent of "show hidden"), minus every path in any folder (user-created included), minus apps where `getCategory(for:) == .system`. This reuses the existing classifier instead of a second prefix test, so the two can never disagree. Never derived from `visibleApplications`, so results don't depend on the "show hidden" toggle. One predicate defines all of this: `@MainActor func LibraryScanState.isSmartFolderCandidate(_ app: Application) -> Bool`. It lives on the main actor because it reads main-actor state (`getCategory(for:)`, `hiddenAppPaths`, `folders`, `appPathIndex`). D5's re-validation reuses it.

**Value boundary:** candidates are filtered **on the main actor** before anything goes to background work. The wizard then passes plain values (`[SmartFolderCandidate]` — `path`, `name`, `Sendable`) into the detached `BundleInfoReader` pass and then into the `nonisolated` `SmartFolderAssigner`. The planner never sees `Application`, `LibraryScanState`, or category/hidden/folder state; it only classifies what it's given.

Known consequence: a wrapper folder with ≥ 2 apps appears only as its own tile; its member apps are never listed individually in `displayOrder`, so they are not classified and stay inside the wrapper tile.

Rerun: assigns only to folders that already exist (key, then name) unless "create missing" is checked. First run: chosen folders are created only if they receive ≥ 1 app.

---

## New/changed files

| File | Change |
|---|---|
| `Services/SmartFolderCatalog.swift` | `SmartFolderCategory` enum (stable keys, localized names), bundle-ID overrides, vendor prefixes, name aliases, `public.app-category.*` mapping table |
| `Services/BundleInfoReader.swift` | `nonisolated` capped Info.plist reader → `(bundleID, lsCategory)` |
| `Services/SmartFolderAssigner.swift` | `nonisolated` pure planner: pre-filtered `[SmartFolderCandidate]` + bundle info → per-folder plan (D2 tiers, ordering). No eligibility logic. |
| `Services/SmartFoldersWizardPanel.swift` | Modal panel + step views |
| `Types.swift` | `AppFolder.smartCategoryKey` + init param (D3) |
| `LibraryScanState.swift` | `isSmartFolderCandidate` (D7), `applySmartFolderBatch`, `undoSmartFolderBatch`, `SmartFolderUndoToken` (D5/D5b) |
| `Services/BackupManager.swift` | `createdByAppVersion`/`minimumAppVersion` on `BackupArchive`, `BackupVersionHeader`, `compatibility(...)`, version comparator, result-enum `decodeArchive` (D3b, phase B); `smartCategoryKey` validation in `apply` (phase 3) |
| `StatusBarManager.swift`, `RestorePreviewPanel.swift` | Refusal alerts per result case; "created by" version + newer-version warning in preview (phase B) |
| `Constants.swift` | `BackupCompatibility.minimumReaderVersion` (D3b); `WizardMetrics` (window size, stagger timing, `maxAnimatedApps`, plist read cap) with rationale comments |
| `StatusBarManager.swift`, `SettingsContentView.swift` | Entry points |
| `Resources/Localizable.xcstrings` | All new strings (folder names, step titles, buttons, summary counts) |
| `Tests/SmartFolderCatalogTests.swift` | No duplicate bundle IDs/aliases; every `SmartFolderCategory` display-name key **exists in `Localizable.xcstrings`** — enforced by parsing the file as JSON (located via `#filePath` relative to the test file) and checking `strings` keys, not via `String(localized:)`, which returns the key even when it's absent; every category has at least one UTI or catalog entry; all mapped UTIs are well-formed |
| `Tests/SmartFolderAssignerTests.swift` | Tier order (override beats UTI, prefix beats UTI, UTI beats alias); exact-name-only; unknown → loose; deterministic order |
| `Tests/BundleInfoReaderTests.swift` | Reads Calculator.app (`XCTSkip` if absent); missing/oversized/garbage plist → nil, no crash |
| `Tests/SmartFoldersWizardTests.swift` | `dataVersion` delta == 1 per apply with no folder open, == 2 with a folder open (and `currentFolderId` is nil afterwards), and == 0 for a no-op apply **both** with and without a folder open (open folder stays open); `isSmartFolderCandidate`: hidden/`.system`/foldered/unindexed excluded, scanner wrapper-folder tile (`isFolder == true`, non-`.app` path) excluded, result independent of `showHiddenApps`; stale plan re-validation (app moved/hidden/removed, folder deleted mid-wizard, plan containing a wrapper-folder path → never written to `appPaths`); no empty folders created; existing membership untouched; rerun idempotent; name-reuse stamps key; rename survives rerun; undo (clean + after intervening change, incl. a membership-only change that `==` would miss; removed paths' folder icons regenerated; undo while a created folder is open closes it, delta == 2) |
| `Tests/BackupIntegrityTests.swift` | `smartCategoryKey` round-trip; old archive without key/version fields decodes; unknown/garbage `smartCategoryKey` is dropped on restore, folder kept; version stamp helper output written into the archive and survives `encodeArchive`/`decodeArchive` (version injected; `createdBy` nil when `appVersion` is nil); payload with extra unknown keys still decodes (simulates 1.0.4 reading a newer backup) |
| `Tests/BackupCompatibilityTests.swift` (phase B) | Comparator (`1.0.10 > 1.0.9`, `1.0` == `1.0.0`, unparseable → compatible); gate: min > current → refuse, created-by newer → warn, missing → ok, unknown current → ok; `schemaVersion` 3 → unsupported; checksum failure still → corrupted; header decodes even when full archive doesn't |
| `AGENTS.md` | File list, wizard rerun/apply invariant, `WizardMetrics`, "Where to change what" row |

`BackupArchive` gains two optional fields (D3b); no `BackupArchive.schemaVersion` or `currentSchemaVersion` bump, no new UserDefaults keys, no `AppModel` members, no dependencies, no network.

---

## Implementation phases (each ends green on `swift build && swift test`)

1. **Catalog** — `SmartFolderCategory`, UTI mapping table, initial overrides/aliases; catalog tests. — **[Done 2026-10-10]** Shipped `Services/SmartFolderCatalog.swift` (9-category enum with localized `displayName`; 4-tier lookup: `byBundleID`, `vendorPrefixes`, `byCategoryUTI`, `byName`) and the nine display-name strings in `Localizable.xcstrings`. `Tests/SmartFolderCatalogTests.swift` (8 tests) enforces localized-name presence (by parsing the `.xcstrings`), per-category coverage, well-formed keys, case-insensitive bundle-ID uniqueness, and no bundle-ID/vendor-prefix conflicts. `swift build` clean; full `swift test` green (789 passed, 3 pre-existing env skips, 0 failures). Bundle IDs grounded in real installed bundles (Safari/Mail/Firefox all declare `productivity` — hence the overrides; design apps use `graphics-design`, finance `finance`). Note: `AGENTS.md` file-list row for the new service is deferred to Phase 6 per the plan.
2. **Engine** — `BundleInfoReader` + `SmartFolderAssigner`; pure tests. — **[Done 2026-10-10]** Shipped `Services/BundleInfoReader.swift` (`BundleInfo` value + a nonisolated, size-capped, fail-soft `Info.plist` reader — never on the scan path; cap is `WizardMetrics.maxInfoPlistReadBytes`, 1 MiB, added to `Constants.swift`) and `Services/SmartFolderAssigner.swift` (`SmartFolderCandidate`/`SmartFolderPlan` values + a pure, deterministic 4-tier `classify`: bundle-ID override → vendor prefix → `LSApplicationCategoryType` UTI → exact normalized name; ordering mirrors `ApplicationSorter.isOrderedBefore(_,_,by:.name)` without building `Application`s). Tests: `BundleInfoReaderTests` (6: real Calculator.app read, controlled plist, missing/oversized/garbage fail-soft) and `SmartFolderAssignerTests` (10: each tier beats the one below using real catalog entries, exact-not-prefix and case/diacritic-insensitive name matching, case-insensitive bundle IDs, unknown→loose, determinism). `swift build` clean; full `swift test` green (805 passed, 3 pre-existing env skips, 0 failures).
3. **Persisted format + Apply + Undo** — `smartCategoryKey` + restore validation, `applySmartFolderBatch`, `undoSmartFolderBatch`; stateful + backup tests. — **[Done 2026-10-11]** Shipped the persisted format and the main-actor apply/undo. `AppFolder.smartCategoryKey: String?` (defaulted, so `FolderStore`/`LaunchieImporter` compile unchanged; optional so old data/backups still decode) + `AppFolder.hasSameContent(as:)` (`Types.swift`). `SmartFolderCategory.sanitizedFolders(_:)` guard, wired into **both** untrusted-data entry points: `BackupManager.apply` and `PreferencesStore.loadFolders` (a bad key is dropped, the folder kept). On `LibraryScanState`: `isSmartFolderCandidate(_:)` (the one eligibility predicate, reused for preview **and** apply re-validation), `applySmartFolderBatch(_:allowCreatingFolders:)` (re-validates, resolves folders by key→name, creates only when allowed with ≥1 app, single `folders` assignment → one persist, closes an open folder first, bumps 0/1/2), and `undoSmartFolderBatch(_:)` (full-restore when unchanged per `hasSameContent`, else surgical: remove added paths, delete now-empty created folders, clear stamped keys). `SmartFolderUndoToken` holds the pre/post snapshots + the change ledger. Tests: `SmartFoldersWizardTests` (26: bump accounting 0/1/2, no-op keeps folder open, candidate exclusions incl. wrapper tiles + show-hidden independence, stale-plan re-validation, no empty folders, rerun idempotency, name-reuse stamps key, rename survives rerun, undo clean + after a membership-only edit that `==` would miss, undo closes a deleted open folder), `SmartFolderCatalogTests` (+4 sanitizer), `BackupIntegrityTests` (+4 key round-trip / no-key decode / garbage-dropped-on-restore), and a UserDefaults garbage-key round-trip. **One deliberate deviation from D5b:** undo regenerates *all* folder composites (`regenerateFolderIcons(changedAppPaths: [])`) rather than passing the removed paths — a removal leaves those paths out of a folder's current membership, so `refreshFolderIcons`' "member is in changedAppPaths" fast path would skip exactly the folders that lost icons; undo is rare, so regenerating all is the correct, simple choice. `swift build` clean; full `swift test` green (839 passed, 3 pre-existing env skips, 0 failures).
4. **Wizard UI** — panel, steps, entry points, localization; manual check via `./create_app_bundle.sh`, confirming every wizard string (including interpolated counts) shows English text, not raw keys, in the built `.app`. — **[Done 2026-10-12]** Shipped the full wizard on top of the Phase-3 engine: `Services/SmartFolderPlanBuilder.swift` (main-actor build: candidates via `isSmartFolderCandidate` → off-main `BundleInfoReader` → `SmartFolderAssigner.classify`), `SmartFoldersWizardViewModel.swift` (`@MainActor @Observable` state machine — `selection`/`preview`/`done`, first-run category selection defaulting to every category with apps, rerun detection by any folder carrying a `smartCategoryKey`, `effectivePlan` filtering, `apply`/`undo`), `SmartFoldersWizardWindow.swift` (a `canBecomeKey` `NSPanel` subclass owned by a `SettingsWindowManager`-style `@MainActor` singleton; a **fresh VM per `show`**), and `SmartFoldersWizardPanel.swift` (three step views + the animation view). Entry points: a "Smart Folders" menu item in `StatusBarManager` and a "Smart Folders Wizard" button in `FoldersSettingsPanel`. All user-visible strings added to `Localizable.xcstrings` (valid JSON; `%lld` for the two interpolated counts, matching the existing `Valid apps to restore: %lld` convention). **Manual check:** built via `./create_app_bundle.sh` and launched the bundle (stays alive, no startup crash) — I could not click through the GUI in this environment, so I verified the localization another way: every wizard string is present in the SPM-compiled `en.lproj/Localizable.strings`, and since each key *is* the English text, `String(localized:)` shows English in the packaged `.app` whether or not the catalog ships (the `BUNDLE_RESOURCES` allowlist does not copy the SPM bundle, a pre-existing condition that equally affects the existing "Restore Backup" string — not a regression). `swift build` clean; full `swift test` green (864 passed, 3 pre-existing env skips, 0 failures).
5. **Animation** — gated recap + `WizardMetrics`. — **[Done 2026-10-12, with Phase 4]** `Services/SmartFoldersAnimation.swift` holds the pure, testable motion math (`progress`/`ease`/`lerp`/two-phase `position`) and the gate `isAnimationAllowed(thermalState:activeCores:reduceMotion:)` (nominal thermal + `≥ minAnimatedCores` active cores + no reduce-motion); the production call site reads `ProcessInfo`/`NSWorkspace`. `WizardMetrics` gained `windowWidth/Height`, `minAnimatedCores`, `maxAnimatedApps`, `animationDuration`, `animationStagger`, `animationClusterPhase` (each rationale-commented). The `WizardAnimationView` drives a `TimelineView(.animation)` off the pure math, caps at `maxAnimatedApps` dots, and swaps to a static end-state (no live timeline) once the last dot has settled — so a lingering preview doesn't keep ticking. The plan preview always shows regardless of the gate, so a failed gate loses no information.
6. **Docs** — `AGENTS.md`/`CODE_REVIEW.md`. — **[Done 2026-10-12, AGENTS.md]** `AGENTS.md` updated per rule 11: new "Smart Folders wizard" row in *Where to change what*; the five new `Services/` files + three top-level wizard files in the repo layout; an `AppFolder.smartCategoryKey` glossary entry (rerun resolves by key→name; validated by `sanitizedFolders`); and the wizard in the *Project overview* feature line. `CODE_REVIEW.md`: no new findings to log (no defects surfaced; the one deliberate D5b deviation was recorded under Phase 3).

**Phase B (separate change, independent of 1–6):** D3b version stamp, header decode, result-enum `decodeArchive`, refusal/warning UI, `BackupCompatibilityTests`. Ends green on `swift build && swift test` on its own.

## Ask-first gates

- ~~`AppFolder.smartCategoryKey` and backup version fields (persisted-format additions)~~ — **approved by owner 2026-10-10**, on condition of backward compatibility (D3b).

No open items.

## Out of scope (noted, not required for this feature)

- `Localizable.xcstrings` does not ship in the `.app` (SPM resource bundle not copied). Not harmless by default: `LocalizationTests` pass regardless, so the runtime behavior must be checked. Keys in this project are the English text itself (e.g. `"All Apps"`), so `String(localized:)` falls back to readable English; phase 4's manual `.app` check confirms this, including interpolated strings. If any string shows a raw key, that is a blocker for phase 4, not out of scope. Real translations need the bundle shipped (ask-first: `build_common.sh`), tracked separately in `CODE_REVIEW.md`.
