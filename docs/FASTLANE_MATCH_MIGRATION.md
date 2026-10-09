# Migrating Existing Signing Certs/Profiles to Fastlane Match

Runbook for bringing the signing identity that already exists on one Mac into
Fastlane Match, so a second (or third) Mac can pull it down instead of each
machine managing its own certs/profiles independently.

Use `match import`, not `match appstore`/`match development` — `import` takes
your *existing* certificate and provisioning profile as-is, so nothing gets
revoked or regenerated and other machines already using them keep working.

---

## 1. Create a storage repo (once)

Done: [`bluefunda/ios-certificates`](https://github.com/bluefunda/ios-certificates)
(private) holds the encrypted certs/profiles, separate from `cai-ios`. It starts
empty — the first `match import` populates it.

## 2. On the Mac that already has the certs/profiles

`fastlane/Matchfile` is already committed (points at the repo above), so
`match init` is not needed.

The first `match import` asks you to set a **passphrase** — this encrypts
everything in the repo. Save it in a shared password manager; you'll need it
on every other machine. Never put it in a file in this repo.

> If `bundle exec` fails with a bundler version error (macOS system Ruby),
> run Homebrew's `fastlane` directly instead of `bundle exec fastlane`.

Export the existing certificate (if not already a `.p12`):

```bash
# Find the certificate name
security find-identity -v -p codesigning | grep "Apple Distribution"
```
Or via Keychain Access: **My Certificates** → *Apple Distribution: BlueFunda, Inc.*
→ right-click → **Export** → save as `.p12`, and **leave the export password
empty**. `match import` copies the `.p12` into the repo as-is, and on every
other machine match installs it with an empty password
(`security import -P ""`) — a password-protected `.p12` imports fine here but
fails everywhere else. The match passphrase is what protects it in the repo.
Write it somewhere outside any git checkout and delete it right after import.

`match import` also needs the public certificate as a `.cer` (not secret):
Keychain Access → same certificate → **Export** → format *Certificate (.cer)*,
or:

```bash
security find-certificate -c "Apple Distribution: BlueFunda, Inc." -p \
  | openssl x509 -outform der -out distribution.cer
```

Import the existing iOS App Store cert + profile:

```bash
bundle exec fastlane match import --type appstore
```
It will prompt for:
- the `.cer` certificate
- the `.p12` private key
- the `BlueFunda AI App Store.mobileprovision` file

Xcode's profile cache usually holds several old copies with the same name —
pick the newest one signed by the Apple Distribution cert. To list them:

```bash
cd ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles
for f in *; do security cms -D -i "$f" 2>/dev/null | plutil -p - | grep -E '"(Name|CreationDate|UUID)"' | tr -s ' ' | paste -sd' ' -; done | grep "BlueFunda AI"
```

Repeat for the Mac Catalyst / macOS App Store profile:

```bash
bundle exec fastlane match import --type appstore --platform macos
```
(for `BlueFunda AI Mac App Store`)

The Mac App Store upload is a signed `.pkg`, which also needs the
**3rd Party Mac Developer Installer** certificate. Export its `.cer` and `.p12`
(empty password) the same way, then:

```bash
bundle exec fastlane match import --type mac_installer_distribution --platform macos
```
(no provisioning profile for this one — skip that prompt.)

Once all imports succeed, **delete the exported `.p12` files** — the
encrypted copies in the match repo are now the source of truth:

```bash
rm -P /path/to/*.p12 /path/to/*.cer
```

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
bundle exec fastlane match mac_installer_distribution --platform macos --readonly
```

Enter the shared passphrase when prompted (or set `MATCH_PASSWORD` as an env
var). This decrypts and installs:
- the certificate + private key into the local Keychain
- the provisioning profile into `~/Library/MobileDevice/Provisioning Profiles/`

## 4. `fastlane/Matchfile`

Already committed. It only holds the storage repo URL/config, no secrets.
`.gitignore` also blocks `*.p12`, `*.cer`, `*.p8`, `*.mobileprovision` and
`*.provisionprofile` so exported signing files can't be committed by accident.

---

See [`docs/CODE_SIGNING.md`](CODE_SIGNING.md) for the broader picture of how
signing works in this project and the other sharing options (GitHub Actions
secrets, Vault).
