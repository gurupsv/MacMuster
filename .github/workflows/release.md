# Releasing MacMuster

This document describes how to cut a release. The actual build, signing,
notarization, packaging, and GitHub Release publication are automated by
`.github/workflows/release.yml` — the manual steps below are the human parts.

## One-time setup (CI signing secrets, optional)

Signing is optional. With no secrets the workflow publishes an ad-hoc-signed,
un-notarized `.pkg` (users get a Gatekeeper warning). Set `P12_BASE64` +
`P12_PASSWORD` to sign, and also `APPLE_ID` + `APPLE_TEAM_ID` +
`APP_SPECIFIC_PASSWORD` to notarize; both need a paid Apple Developer Program
membership. A partial set fails the run.

Configure these as repository secrets under **Settings → Secrets and
variables → Actions**:

| Secret                  | Description                                                                 |
|-------------------------|-----------------------------------------------------------------------------|
| `P12_BASE64`            | `base64` of your *Developer ID Application* `.p12` certificate.             |
| `P12_PASSWORD`          | Password used when exporting that `.p12`.                                   |
| `INSTALLER_P12_BASE64`  | `base64` of your *Developer ID Installer* `.p12` (separate certificate).    |
| `INSTALLER_P12_PASSWORD`| Password for the installer `.p12`.                                          |
| `APPLE_ID`              | Apple ID (email) of the developer account.                                  |
| `APPLE_TEAM_ID`         | Team ID from developer.apple.com → Membership.                              |
| `APP_SPECIFIC_PASSWORD`  | App-specific password for `notarytool` (create at appleid.apple.com).       |

Export the certificates from Keychain Access as `.p12`, then:

```bash
base64 -i "Developer ID Application.p12" | pbcopy    # → P12_BASE64
base64 -i "Developer ID Installer.p12"   | pbcopy    # → INSTALLER_P12_BASE64
```

> Keep the `.p12` files out of the repo. They are not committed anywhere.

## Cutting a release

1. **Update `version.txt`** to the new version (e.g. `1.0.3`). This is the
   single source of truth for `CFBundleShortVersionString` and the cask version.
2. **Commit** the bump: `git commit -am "Release 1.0.3"`.
3. **Tag** the commit with the *exact* same string as `version.txt`:
   ```bash
   git tag 1.0.3
   git push origin master --tags
   ```
4. The `Release` workflow runs automatically. It:
   - verifies the tag matches `version.txt`,
   - builds a universal binary (`BUILD_UNIVERSAL=1`),
   - signs with the Developer ID Application cert,
   - notarizes + staples via `notarytool`,
   - builds and signs the `.pkg` with the Developer ID Installer cert,
   - creates a GitHub Release named `MacMuster <version>`,
   - attaches `MacMuster-<version>.pkg`,
   - prints the `sha256` in the release notes.
5. **Watch the run** under the Actions tab. Notarization can take a few
   minutes; the job timeout is 30m.
6. When it finishes, open the Release on GitHub and check the `.pkg` is
   attached. The Homebrew cask updates itself (see
   [Homebrew cask](#homebrew-cask-automatic)); no manual sha copy is needed.

## Homebrew cask (automatic)

The cask lives in a separate repo, `gurupsv/homebrew-macmuster`
(`Casks/m/macmuster.rb`). Its workflow `.github/workflows/update-cask.yml`
polls this repo's latest release hourly (at :17), downloads the `.pkg`,
computes its sha256, and commits the new `version` and `sha256` to the tap's
`main` branch. It uses the tap's own `GITHUB_TOKEN`, so this repo holds no
token for it.

- **Pre-releases are skipped.** Only a published, non-draft release with a
  plain `X.Y.Z` tag counts; it never downgrades.
- **To skip the wait**, run it by hand once the Release shows the `.pkg`:
  tap repo → Actions → *Update cask* → *Run workflow*.
- **If the `.pkg` is not uploaded yet**, the run fails and the next hour
  retries.
- **Verify** with `brew update && brew info --cask gurupsv/macmuster/macmuster`
  (shows the new version).
- GitHub pauses scheduled workflows after 60 days without repo activity; each
  cask bump counts as activity. After a long gap, re-enable the workflow from
  the tap's Actions tab.

## Local release build (fallback)

If you ever need to produce the artifact on your own Mac instead of CI:

```bash
BUILD_UNIVERSAL=1 \
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
INSTALLER_ID="Developer ID Installer: Your Name (TEAMID)" \
NOTARY_PROFILE="macmuster-notary" \
./build_production.sh
```

Then manually create the GitHub Release and upload `MacMuster-<version>.pkg`,
and record `shasum -a 256 MacMuster-<version>.pkg`.

## What each release produces

| File                          | Purpose                                                |
|-------------------------------|--------------------------------------------------------|
| `MacMuster-<version>.pkg`     | Signed+notarized installer; GitHub Release asset.      |
| `sha256` (in release notes)   | For manual verification; the tap workflow computes its own for the cask. |

The release URL is stable and immutable:

```
https://github.com/gurupsv/MacMuster/releases/download/<version>/MacMuster-<version>.pkg
```

That URL is what the cask's `url` stanza points at.