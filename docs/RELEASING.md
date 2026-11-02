# Releasing

Releases are built, signed with the **Developer ID Application** certificate, notarized by Apple and
published by `.github/workflows/release.yml` when a version tag is pushed.

## Every release

1. Move the `[Unreleased]` notes in `CHANGELOG.md` under a new version heading and update the links at
   the bottom.
2. Commit, then tag and push:

   ```sh
   git tag v1.0.1
   git push origin v1.0.1
   ```

3. The workflow sets the version from the tag, builds, signs, notarizes and staples the app, packs
   it into `CmdTab-v1.0.1.dmg` (signed, notarized and stapled too) and `CmdTab-v1.0.1.zip`, and
   attaches both with `SHA256SUMS` to a new GitHub release.

To rebuild the files of a release that already exists, run the **Release** workflow by hand
(Actions → Release → Run workflow) with its tag. It builds from the branch you pick and replaces the
release's files.

The DMG layout lives in `Resources/dmg/` (`settings.py` for dmgbuild, the background exported from
the "DMG / Background" frame in the design file). Build one locally with
`scripts/make-dmg.sh path/to/CmdTab.app build/CmdTab.dmg`.

## One-time setup: repository secrets

Settings → Secrets and variables → Actions → **New repository secret**.

### Signing certificate

The certificate Xcode manages in the cloud can't be exported, so create one with a local private key:

1. Xcode → Settings → Accounts → select the team → **Manage Certificates…** → **+** →
   **Developer ID Application**.
2. Keychain Access → My Certificates → right-click **Developer ID Application: …** → **Export…** →
   save as `developer-id.p12` with a strong password.
3. Add the secrets:

   | Secret | Value |
   |---|---|
   | `DEVELOPER_ID_P12_BASE64` | `base64 -i developer-id.p12 \| pbcopy`, then paste |
   | `DEVELOPER_ID_P12_PASSWORD` | the export password |

4. Delete `developer-id.p12` from disk.

### Notarization API key

1. [App Store Connect](https://appstoreconnect.apple.com/access/integrations/api) → Users and Access →
   Integrations → App Store Connect API → Team Keys → **+**, access **Developer**.
2. Download the `.p8` (only possible once) and note the **Key ID** and the **Issuer ID** above the list.
3. Add the secrets:

   | Secret | Value |
   |---|---|
   | `NOTARY_KEY_P8_BASE64` | `base64 -i AuthKey_XXXX.p8 \| pbcopy`, then paste |
   | `NOTARY_KEY_ID` | the Key ID |
   | `NOTARY_ISSUER_ID` | the Issuer ID |

4. Delete the `.p8` from disk; revoke the key in App Store Connect if it ever leaks.

## Releasing from a Mac instead

With the Apple ID signed in to Xcode (Settings → Accounts), Xcode can sign with its cloud-managed
Developer ID certificate and notarize with the account, no secrets needed:

```sh
xcodebuild -project CmdTab.xcodeproj -scheme CmdTab -configuration Release \
  -archivePath build/CmdTab.xcarchive archive
xcodebuild -exportArchive -archivePath build/CmdTab.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/upload -allowProvisioningUpdates
# ExportOptions.plist: method developer-id, teamID RQTYDUV329, signingStyle automatic, destination upload
xcodebuild -exportNotarizedApp -archivePath build/CmdTab.xcarchive -exportPath build/notarized
```

`-exportNotarizedApp` fails until Apple has finished; retry after a minute. The result is already
stapled.
