# Releasing MacMuster

This document describes how to cut a release. The actual build, signing,
notarization, packaging, and GitHub Release publication are automated by
`.github/workflows/release.yml` — the manual steps below are the human parts.

## One-time setup (CI signing secrets)

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
6. When it finishes, open the Release on GitHub and **copy the `sha256`**
   from the release notes — the next phase (Homebrew cask) needs it.

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
| `sha256` (in release notes)   | Pasted into the Homebrew cask's `sha256` stanza.       |

The release URL is stable and immutable:

```
https://github.com/gurupsv/MacMuster/releases/download/<version>/MacMuster-<version>.pkg
```

That URL is what the cask's `url` stanza points at.