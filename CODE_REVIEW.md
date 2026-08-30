# MacMuster — Code Review Findings

Full-codebase review (8,223 lines / 32 files) performed **2026-08-29** against commit `6102564` on `master`.

Tick a checkbox when a finding is fixed, and note the fixing commit next to it. Items are grouped
by category and carry stable IDs (`CRIT-1`, `SEC-2`, …) so they can be referenced from commit
messages and issues.

## Progress

| Category | Total | Done | Pending |
|---|---:|---:|---:|
| Critical | 1 | 1 | 0 |
| Security | 4 | 3 | 1 |
| Performance | 6 | 4 | 2 |
| Usability | 9 | 5 | 4 |
| Other bugs | 9 | 5 | 4 |
| **Total** | **29** | **18** | **11** |

Next up: `UX-6`/`UX-7` (custom order overriding sort, and unstable ordering), then
`UX-8`/`UX-9` and the remaining `BUG-` items.

---

## 🔴 Critical

### [x] CRIT-1 — Backup restore always fails; every backup is unusable — **FIXED**

> **Fixed 2026-08-29.** Introduced a `BackupFile` container whose checksum covers the encoded
> payload's bytes exactly as written, so verification never re-encodes the archive. Re-encoding
> could not have worked: `hiddenAppPaths` is a `Set<String>`, which encodes to a JSON array in
> per-process iteration order. Extracted `encodeArchive`/`decodeArchive`/`sha256Hex` as
> `nonisolated` statics so the integrity path is testable without an `NSSavePanel`.
> Covered by `Tests/BackupIntegrityTests.swift` (13 tests). Legacy flat archives still decode.


**Where:** `Sources/MacMuster/Services/BackupManager.swift:240-254` (export), `:271` (verify)

`export()` computes SHA256 over JSON containing an *empty* checksum placeholder, writes that digest
into the file, then computes a second digest and assigns it to a local that is never re-encoded.
`restore()` hashes the entire file — checksum field included — so the stored and computed digests
can never match, and restore returns `nil` every time.

Verified by running the exact export/verify logic in isolation: the two digests differ, so
`restore()` returns `nil` for every v2 archive.

**Fix:** hash with the checksum field zeroed on *both* sides, or hash only the payload fields and
exclude `checksum` from the digest input. Drop the dead second assignment either way.

**Related:** `BUG-7` (no test covers this path).

---

## 🔒 Security

### [x] SEC-1 — Arbitrary file write via malicious backup (path traversal) — **FIXED**

> **Fixed 2026-08-29.** `restoreIconPack` now accepts only keys matching the exact shape the cache
> writes (64-char lowercase ASCII hex), plus a containment check that the resolved write path is
> still inside the cache directory. `readIconPack` filters on export too. Verified non-vacuously:
> with the guard removed the new test fails and really does write
> `~/Library/macmuster-sec1-escape.txt`; with it restored, it passes and a valid key alongside the
> hostile ones is still restored.


**Where:** `Sources/MacMuster/Services/BackupManager.swift:415`

Icon-pack keys are read from untrusted backup JSON and passed straight to
`cacheDir.appendingPathComponent(key, isDirectory: false)`, then written with `Data.write(to:)`.
A key such as `../../../../evil.txt` resolves outside the cache directory — confirmed by test.
`~/Library/LaunchAgents/` is reachable this way, making it a persistence vector.

Exploitable today: an archive with `checksum: ""` skips verification entirely (`:270`), so `CRIT-1`
does not incidentally protect against this.

**Fix:** reject any key that is not a 64-character lowercase hex string (the real cache-key format
produced by `IconCacheManager.cacheKey`). Belt-and-braces: verify the resolved path is still inside
`cacheDir` before writing.

### [x] SEC-2 — Provenance badge is bypassable — **FIXED**

> **Fixed 2026-08-30.** `Application` precomputes `resolvedPath` (lexical `..` removal, then
> `realpath`) and the trust check runs against that. Both steps are needed: `realpath` returns
> nil for a path that does not exist, so a traversal string would otherwise fall back to the
> raw prefix it was built to fake.
>
> **This nearly shipped a worse bug.** Resolving paths naively flags Safari as untrusted: on
> current macOS `/Applications/Safari.app` resolves to
> `/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app`. The SIP-protected
> cryptex is now an explicit trusted prefix, with a regression test pinning it.


**Where:** `Sources/MacMuster/Types.swift:92-95`

`isFromTrustedLocation` is a raw string prefix check on an uncanonicalized path, so
`/Applications/../tmp/Fake.app` reads as trusted, as does a symlink placed under `/Applications`
pointing anywhere. `ApplicationScanner` also stores unresolved paths (`fullPath`, not
`resolvedPath`), so the value being checked is attacker-influenced.

This defeats the security feature the README advertises.

**Fix:** canonicalize with `realpath(3)` (see `DirectoryWatcher.canonicalPath`) before the prefix
check, and consider storing the resolved path on `Application`.

### [x] SEC-3 — Checksum is documented as tamper detection but cannot be — **FIXED**

> **Fixed 2026-08-29** alongside `CRIT-1`. The "corrupted or tampered" wording is gone; the
> verification path now reads "Corrupted or truncated in transit", and `BackupFile`'s doc comment
> states what the checksum does and does not cover.


**Where:** `Sources/MacMuster/Services/BackupManager.swift:16`, `:274`

An attacker controls both the archive and its checksum field, so the digest can only ever detect
accidental corruption — never tampering. The comment at `:274` ("corrupted or tampered") overstates
it and could lead someone to trust a restored archive.

**Fix:** relabel in comments as corruption detection only. (Fix alongside `CRIT-1`.)

### [ ] SEC-4 — `isValidCustomDirectory` is TOCTOU

**Where:** `Sources/MacMuster/Services/ApplicationScanner.swift:222-241`

Symlink and world-writable checks run only when a directory is added. The directory can be replaced
with a symlink afterwards, and every later scan follows it. Low severity given the threat model
(local user, own machine), but the guarantee is weaker than the function name implies.

**Fix:** re-validate at scan time, or document the limitation.

---

## ⚡ Performance

### [x] PERF-1 — Icon mtime cache never refreshes, defeating icon invalidation — **FIXED**

> **Fixed 2026-08-29.** Turned out to be **two** defects, either of which alone keeps the bug
> alive:
>
> 1. `currentBundleModificationTime` short-circuited on the cached value, and that cache was only
>    ever written by that same method — so nothing re-read the disk after the first read of a path.
>    It now always stats and writes through.
> 2. `cachedIcon` returned in-memory hits before checking anything, and `loadMissingIcons(force:)`
>    re-loads *through* `cachedIcon` — so a correct disk-layer check would still have been handed
>    the stale image out of memory. Added `memoryEntryMtime`, recording the mtime each in-memory
>    image was rendered for, so a memory hit is validated for the cost of one `stat` and none of
>    the disk reads the memory layer exists to skip.
>
> Also dropped the no-op mtime "refresh" pass from `pruneDeletedApps` (it wrote each stale entry
> back over itself), and pointed `refreshCachedIcons` at a fresh disk read instead of the
> in-memory record — that comparison was a number against itself.
>
> Covered by `Tests/IconStalenessTests.swift` (7 tests) driving real files whose mtimes move on
> disk. Verified non-vacuous against *each* defect separately: restoring defect 1 fails 5 of 7,
> restoring defect 2 alone still fails 3 of 7. Suite: 634 → 641.
>
> **Behaviour change:** `cacheIcon` no longer stores an entry for a path whose mtime cannot be
> read, since such an entry can never be validated. Two tests in `IconCacheManagerTests` asserted
> the old behaviour and were updated; one of them contradicted its own neighbour
> (`testCachedIconForNonExistentPathReturnsNil`) and passed only by ordering luck.


**Where:** `Sources/MacMuster/Services/IconCacheManager.swift:305` and `:257-261`

`currentBundleModificationTime` returns the cached value when one exists. `pruneDeletedApps`
"refreshes" the cache by calling *that same function* — so it reads the stale value and writes it
straight back. The mtime cache is effectively write-once per session. The comment at `:49-50`
claims the opposite ("refreshed during pruneDeletedApps so they stay accurate").

Consequences:
- `refreshCachedIcons()` (the 6-hourly job) can never detect a stale icon — its entire purpose.
- An app updated while MacMuster is running keeps its old icon for the rest of the session.
- Nondeterministic in practice, since `NSCache` may evict entries under memory pressure and force
  a genuine re-stat.

**Fix:** give `currentBundleModificationTime` a `forceRefresh` parameter (or a separate
`refreshMtime`) and use it from `pruneDeletedApps`.

### [x] PERF-2 — `findContainedApps` runs for every discovered app — **FIXED**

> **Fixed 2026-08-30.** Dropped the listing of each bundle's own root. Measured across 210
> bundles in `/Applications`, `/System/Applications` and `/System/Applications/Utilities`:
> **zero** had a root-level `.app` child, while 2 had one of the nested directories — so that
> was 210 directory reads per scan that could not succeed. The two nested paths that actually
> carry apps are still checked, now by enumerating directly instead of `fileExists` first.


**Where:** `Sources/MacMuster/Services/ApplicationScanner.swift:56`, `:146-184`

Every `.app` gets a `contentsOfDirectory` call plus two `fileExists` probes on hardcoded nested
paths, though almost no apps nest bundles. At ~200 apps that is 600+ extra syscalls per scan, and
scans fire on every filesystem event, not just at launch.

**Fix:** probe nested paths lazily, or gate on a cheap heuristic before enumerating.

### [ ] PERF-3 — O(n²) dictionary pruning in the update tracker

**Where:** `Sources/MacMuster/Services/RecentlyUpdatedTracker.swift:71-76`

Both loops mutate a dictionary while iterating its own `.keys` view. This is *safe* (copy-on-write
saves it) but forces a full dictionary copy per removal.

**Fix:** collect the paths to remove first, then remove them in a second pass.

### [x] PERF-4 — Redundant back-to-back `fileExists` calls — **FIXED**

> **Fixed 2026-08-30.** Scanner occurrences removed: `attributesOfItem` already reports a
> missing path by failing, and `.isDirectoryKey` arrives with the enumeration instead of
> costing a stat per entry. The `BackupManager` occurrence was done earlier with `CRIT-1`.


**Where:** ~~`Sources/MacMuster/Services/BackupManager.swift:285` and `:290`~~ (done); several
spots in `ApplicationScanner` (pending)

Each call is a syscall; one `fileExists(atPath:isDirectory:)` answers both questions.

> **Partially fixed 2026-08-29.** The `BackupManager.restore()` occurrence was collapsed into a
> single stat while fixing `CRIT-1`. The `ApplicationScanner` occurrences remain.

### [x] PERF-5 — `findAppsInPlainFolder` has no symlink-cycle guard — **FIXED**

> **Fixed 2026-08-30.** The walk no longer descends through symlinks. Confirmed against the
> original implementation: a folder containing a link to itself yielded the same app **5
> times** (`loop/loop/loop/loop/`), and worse, the duplicates pushed the folder over the
> "2 or more apps" threshold so it surfaced as a synthetic folder instead of the app.
>
> No visited-path set: the URL-based `contentsOfDirectory(at:)` will not open a symlinked
> directory at all (the string-based API it replaced followed it happily), so cycles are
> structurally impossible. An earlier draft carried a canonical-path set as a backstop — it
> was unreachable, and sabotage testing is what exposed that it was dead code.


**Where:** `Sources/MacMuster/Services/ApplicationScanner.swift:197-215`

Recurses to depth 4 with no symlink protection. A symlink to `/` inside a wrapper folder would walk
an enormous tree. Depth-bounded, so not unbounded, but still a potential multi-second stall.

**Fix:** skip symlinked directories, or track visited canonical paths.

### [ ] PERF-6 — Icons under-rasterized at the largest size

**Where:** `Sources/MacMuster/Constants.swift:116` (`iconRasterPixelSizePx = 160`)

Extra Large is 100 pt = 200 px on a 2× display, so the largest icon size renders slightly soft.

**Fix:** raise to 200 px, or scale the raster size with the icon-size setting.

---

## 🧭 Usability

### [x] UX-1 — The running dot is frozen at app launch (regression in shipped feature) — **FIXED**

> **Fixed 2026-08-29.** `RunningAppTracker` gained an `onChange` hook, published from a `didSet`
> on `runningAppPaths` so *every* mutation path (snapshot, launch, terminate, direct assignment)
> notifies, and only on a real change. `AppDelegate` installs the hook **before** `start()`, so
> the initial snapshot arrives through the same route as every later update; the one-time `Set`
> copy is gone.
>
> Also removed the `dataVersion += 1` from `LibraryScanState.runningAppPaths`. Nothing in display,
> sort, navigation or folder logic reads that set (verified), and now that updates are live it
> would have rebuilt the whole grid on every system-wide launch/quit. `@Observable` re-renders the
> affected cells on its own.
>
> Covered by `Tests/RunningAppBadgeLivenessTests.swift` (6 tests). Verified non-vacuous: with the
> hook stubbed out, 5 of the 6 fail. Suite: 628 → 634.


**Where:** `Sources/MacMuster/AppDelegate.swift:42`

```swift
appModel.library.runningAppPaths = RunningAppTracker.shared.runningAppPaths
```

`Set` is a value type, so this is a one-time snapshot. `RunningAppTracker`'s launch/terminate
observers update *its own* set; nothing ever propagates into `library.runningAppPaths`, which is
what the UI reads. Apps launched or quit after startup never change their dot.

The comment at `:38-40` asserts the observers keep it current — they do not.

**Fix:** give `RunningAppTracker` an `onChange` callback that pushes into `library.runningAppPaths`,
or have the view read the tracker directly.

### [x] UX-2 — Restore appears to do nothing until relaunch — **FIXED**

> **Fixed 2026-08-29.** Added `reloadFromPersistence()` to `SettingsAppearance` and
> `LibraryScanState`, and `AppModel.reloadAfterRestore()` tying them together with the badge
> trackers. `StatusBarManager` calls it on both restore paths. `SettingsAppearance.init` now
> routes through the same method rather than duplicating the load.


**Where:** `Sources/MacMuster/Services/BackupManager.swift:306-373`

`apply()` writes `PreferencesStore` and `FolderStore.shared.folders`, but never updates
`LibraryScanState.folders` or `SettingsAppearance` — the in-memory state that actually drives the
UI. Note `LibraryScanState.folders`'s `didSet` pushes *to* `FolderStore`, not from it. The user
sees a "Restore Complete" dialog and no visible change.

**Fix:** after `apply()`, reload settings and folders into the live model (or trigger a full reload).

### [x] UX-3 — Closing the restore preview with the red button hangs the flow — **FIXED**

> **Fixed 2026-08-29.** `RestorePreviewPanel` conforms to `NSWindowDelegate` and resumes with
> `.cancel` in `windowWillClose`. `complete` now takes the continuation before resuming, so
> the extra completion path cannot double-resume (which would trap).


**Where:** `Sources/MacMuster/Services/RestorePreviewPanel.swift:48-61`

The window has `.closable` in its style mask but no `NSWindowDelegate`. Closing it via the title-bar
button never calls `complete(with:)`, so the `CheckedContinuation` is never resumed — the awaiting
task hangs forever and Swift may log a continuation-leak warning.

**Fix:** set a delegate and resume with `.cancel` in `windowWillClose`, or drop `.closable`.

### [x] UX-4 — Refresh-interval changes need a restart — **FIXED**

> **Fixed 2026-08-29.** Split `setupRefreshTimer` so the scan timer can be rebuilt on its own
> (`rescheduleRefreshTimer`) without restarting the six-hourly icon-cache timer, which used to
> be recreated alongside it. `SettingsAppearance` publishes through `onRefreshIntervalChange`,
> wired by `AppModel` — the setting cannot reach `LibraryScanState` directly because it is not
> a singleton.


**Where:** `Sources/MacMuster/LibraryScanState.swift:183-195`, called only from `:146`

`setupRefreshTimer()` runs once from `startLoading`. Changing the interval in Settings persists the
value but never reschedules the timer.

**Fix:** call `setupRefreshTimer()` from the `refreshInterval` setter.

### [x] UX-5 — Overlay opacity and presentation mode need a restart — **FIXED**

> **Fixed 2026-08-29.** Extracted `applyBackgroundColor()` as the single place the launcher's
> background is decided, and exposed `refreshAppearance()` for the settings to call. Also
> re-applied at the end of `applyWindowMode`, since changing `styleMask`/`isOpaque` per mode
> can reset it, and extended to the dimming windows on other displays. Tint colour and tint
> strength repaint too — they feed the Sheet background, not just the opacity slider.


**Where:** `Sources/MacMuster/OverlayWindowManager.swift:159-166` (set only in `setup()`);
`Sources/MacMuster/SettingsAppearance.swift:50-56`, `:107-109`

The overlay window's `backgroundColor` is assigned once during setup. Both settings persist and
update the model, but `applyCurrentMode()` (wired only to `launchMode`) never reassigns the colour.

**Fix:** recompute `backgroundColor` in `applyCurrentMode()` and call it from both setters.

### [ ] UX-6 — One drag permanently disables the sort setting and "Show Folders First"

**Where:** `Sources/MacMuster/LibraryScanState.swift:364`;
`Sources/MacMuster/LibraryScanState+Display.swift:145-150`

Once `customOrder` is non-empty it wins in both places — including overwriting the folders-first
arrangement computed a few lines earlier (`folderFirstApplied` is set, then discarded). The Sort
menu appears broken with no way to recover. `setSortOption` clears `customOrder`, but
`showFoldersFirst` has no such escape and nothing signals to the user what happened.

**Fix:** apply custom order *within* the folders-first partition rather than across it, and add a
visible "Reset custom order" affordance.

### [ ] UX-7 — Apps without a custom order shuffle between scans

**Where:** `Sources/MacMuster/LibraryScanState.swift:365-368`;
`LibraryScanState+Display.swift:146-149`; `Services/FolderStore.swift:69-77`

The comparator returns "equal" for every pair of un-ordered apps, and Swift's `sort` is not stable,
so newly installed apps change position between scans.

**Fix:** add a deterministic tiebreaker (`lowercaseName`).

### [ ] UX-8 — Status badges are invisible to VoiceOver

**Where:** `Sources/MacMuster/ContentView.swift:766-767` and `:829-830`

Both badges set `.accessibilityLabel(...)` and then immediately `.accessibilityHidden(true)`, which
nullifies the label. The tile's own label (`accessibilityLabel(for:)`, `:495-504`) does not mention
running or recently-updated state either, so neither badge is perceivable non-visually.

**Fix:** fold both states into `accessibilityLabel(for:)` and keep the decorative overlays hidden.

### [ ] UX-9 — Folders cannot be found by search

**Where:** `Sources/MacMuster/LibraryScanState+Display.swift:104-109`

At root level `applySearchFilter` discards its `apps` argument and searches `visibleApplications`,
which contains no synthetic folder entries — so folder names never match. It also drops the
`folderId` values populated one step earlier in the pipeline.

**Fix:** search the passed-in list (which already includes folder entries and `folderId`s).

---

## 🐛 Other bugs

### [x] BUG-1 — Backup writes a 30 s refresh interval where the app defaults to 300 s — **FIXED**

> **Fixed 2026-08-29.** Added `ScanMetrics.refreshIntervalDefault` and pointed all four sites
> at it, so the value cannot drift apart again.


**Where:** `Sources/MacMuster/Services/BackupManager.swift:166`

`loadRefreshInterval() ?? 30.0` — every other site uses `?? 300`. A backup taken on a fresh install
bakes in rescans 10× more aggressive than intended, and restoring it applies that.

### [x] BUG-2 — Folder timestamps are reset on restore — **FIXED**

> **Fixed 2026-08-29.** `apply` copies the decoded folder and edits `appPaths`, instead of
> rebuilding it through the initializer that stamps `Date()`.


**Where:** `Sources/MacMuster/Services/BackupManager.swift:318-323`

The 4-argument `AppFolder` initializer sets `createdAt`/`modifiedAt` to `Date()`, so restoring
silently discards the original timestamps that were faithfully stored in the archive.

**Fix:** add an initializer that preserves both, or decode the folder unchanged.

### [ ] BUG-3 — `gridColumns` mutates `@State` during view-body evaluation

**Where:** `Sources/MacMuster/ContentView.swift:26-34`

`gridColumnCache = (count, columns)` is a state write inside a computed property read from `body`.
Undefined behaviour in SwiftUI; can trigger "Modifying state during view update" and re-render loops.

**Fix:** compute from `columnCount` without caching (it is cheap), or move the cache off `@State`.

### [x] BUG-4 — Apps get a permanent spurious "recently updated" badge — **FIXED**

> **Fixed 2026-08-30.** An unreadable mtime now falls back to `.distantPast` rather than
> `Date()`. The old fallback moved on every scan, so the tracker saw a fresh delta each time
> and re-badged the app forever — and sorting by installation date shuffled it around too.


**Where:** `Sources/MacMuster/Services/ApplicationScanner.swift:55`, `:131`

When `attributesOfItem` fails the scanner falls back to `Date()`, so that app's recorded mtime moves
on every scan and `RecentlyUpdatedTracker` re-badges it forever.

**Fix:** skip apps whose mtime cannot be read rather than substituting `now`.

### [ ] BUG-5 — `lockFocus`/`unlockFocus` called off the main thread

**Where:** `Sources/MacMuster/Services/IconService.swift:46-51`, reached from `:134-142` via the
cooperative pool in `loadMissingIcons`

The fallback rasterization path uses `NSImage.lockFocus`, which AppKit documents as main-thread
only. Currently a rarely-taken fallback, but a real latent crash/corruption risk.

**Fix:** replace the fallback with a `CGContext`-based path (as the primary path already uses).

### [ ] BUG-6 — Misleading name: `getAllAppsIncludingChildFolders` does not recurse

**Where:** `Sources/MacMuster/Services/FolderStore.swift:56-83`

Returns only the folder's direct members. Either implement nesting or rename.

### [x] BUG-7 — No test covers the export → restore round trip — **FIXED**


**Where:** `Tests/BackupManagerTests.swift`

All 15 backup tests construct `BackupArchive` directly and round-trip it through
`JSONEncoder`/`JSONDecoder`. None exercises `export()` → `restore()`, which is exactly why `CRIT-1`
shipped with 615 passing tests.

**Fix:** extract the checksum computation into a pure, testable function and add a round-trip test
over it.

> **Fixed 2026-08-29.** `Tests/BackupIntegrityTests.swift` adds 13 tests covering the encode→decode
> round trip, Set-ordering stability, corruption/truncation/tamper rejection, legacy decode, and
> the SEC-1 traversal defence. Suite went 615 → 628, all passing.

### [ ] BUG-8 — Dead code

- ~~`RunningAppTracker.didChangeScreenObserver`~~ — **removed 2026-08-29** alongside `UX-1`.
- `LibraryScanState.loadFolders()` — `LibraryScanState.swift:157-159`, never called (the initializer
  inlines the same logic).
- `NSWorkspace.shared.notificationCenter.removeObserver(self)` — `LibraryScanState.swift:247`;
  `LibraryScanState` never registers as an observer.
- `NavigationSelection.swift:129` (`launchApplication(at:appModel: nil)`) — unreachable in
  production today, since the only caller guards on `app.isFolder` and the folder branch returns
  first. Latent: wiring `launchSelectedApp` to a new key path would silently stop recording launches
  and skip dismissing the launcher.

### [x] BUG-9 — Backed-up icons can never be used after restore — **FIXED**

> **Fixed 2026-08-29.** The pack now carries `.meta` sidecars alongside bitmaps, and ships only
> complete pairs. Key validation extended to sidecars via `isValidIconPackKey`, keeping the
> SEC-1 traversal guard intact for both halves.


**Where:** `Sources/MacMuster/Services/BackupManager.swift` — `readIconPack` (skips `.meta` files)
vs `IconCacheManager.cachedIcon` (`:112-115`)

Found while fixing `SEC-1`. `readIconPack` deliberately skips `.meta` sidecar files, so an archive
carries only the bare icon bitmaps. But `cachedIcon` requires **both** the icon file *and* its
`.meta` sidecar to exist before it will read a cache entry — so every restored icon is ignored and
re-decoded from scratch. The icon pack is pure archive bloat today (it is the largest part of a
backup).

**Fix:** include the `.meta` sidecars in the pack (they are small JSON), or drop the icon pack
entirely and let icons re-decode on first run. Note that a restored `.meta` records the source
machine's `bundleMtime`, so entries should be validated against local mtimes on restore.

---

## Notes

- All 615 existing tests passed at the time of review; the findings above are not caught by the
  current suite.
- `CRIT-1` and `SEC-1` were verified by executing the relevant logic in isolation, not by
  inspection alone. `UX-1` was confirmed by tracing the value-type copy at `AppDelegate.swift:42`.
