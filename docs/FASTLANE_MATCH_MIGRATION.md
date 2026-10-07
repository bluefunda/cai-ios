# Migrating Existing Signing Certs/Profiles to Fastlane Match

Runbook for bringing the signing identity that already exists on one Mac into
Fastlane Match, so a second (or third) Mac can pull it down instead of each
machine managing its own certs/profiles independently.

Use `match import`, not `match appstore`/`match development` — `import` takes
your *existing* certificate and provisioning profile as-is, so nothing gets
revoked or regenerated and other machines already using them keep working.

---

## 1. Create a storage repo (once)

Create a new **private** git repo to hold the encrypted certs/profiles,
separate from `cai-ios` (e.g. `bluefunda/ios-certificates`). It doesn't need
any content yet — `match init` will populate it.

## 2. On the Mac that already has the certs/profiles

```bash
cd cai-ios
bundle exec fastlane match init
```
- Choose `git` storage, point it at the new private repo's URL.
- This creates `fastlane/Matchfile`.
- Set a **passphrase** — this encrypts everything in the repo. Save it in a
  shared password manager; you'll need it on every other machine.

Export the existing certificate (if not already a `.p12`):

```bash
# Find the certificate name
security find-identity -v -p codesigning | grep "Apple Distribution"
```
Or via Keychain Access: **My Certificates** → *Apple Distribution: BlueFunda, Inc.*
→ right-click → **Export** → save as `.p12`, set an export password.

Import the existing iOS App Store cert + profile:

```bash
bundle exec fastlane match import --type appstore
```
It will prompt for:
- the `.p12` certificate (+ its export password)
- the `BlueFunda AI App Store.mobileprovision` file

Repeat for the Mac Catalyst / macOS App Store profile:

```bash
bundle exec fastlane match import --type appstore --platform macos
```
(for `BlueFunda AI Mac App Store`)

`match import` preserves the original profile names, so the existing
`Fastfile` mapping keeps working untouched:

```ruby
provisioningProfiles: {
  "com.bluefunda.ai" => "BlueFunda AI App Store"
}
```

## 3. On every other Mac

Make sure git access to the storage repo is set up (SSH key/token), then:

```bash
cd cai-ios
bundle exec fastlane match appstore --readonly
bundle exec fastlane match appstore --platform macos --readonly
```

Enter the shared passphrase when prompted (or set `MATCH_PASSWORD` as an env
var). This decrypts and installs:
- the certificate + private key into the local Keychain
- the provisioning profile into `~/Library/MobileDevice/Provisioning Profiles/`

## 4. Commit `fastlane/Matchfile`

`Matchfile` only holds the storage repo URL/config, no secrets — safe to
commit to `cai-ios`.

---

See [`docs/CODE_SIGNING.md`](CODE_SIGNING.md) for the broader picture of how
signing works in this project and the other sharing options (GitHub Actions
secrets, Vault).
