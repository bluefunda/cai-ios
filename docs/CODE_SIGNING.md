# Code Signing & Certificate Management

How signing works, what files are involved, and how to share them across developers and CI.

---

## How iOS Code Signing Works

Three things must align to sign a build:

```
Distribution Certificate (.p12)
  + Provisioning Profile (.mobileprovision)
  + App ID (com.bluefunda.ai)
  = Signed .ipa
```

| File | What it proves | Where it lives |
|---|---|---|
| `.p12` certificate | You are BlueFunda, Inc. | Your Mac Keychain |
| `.mobileprovision` | This app is authorised for this distribution method | `~/Library/MobileDevice/Provisioning Profiles/` |
| Private key (inside `.p12`) | Only you can sign | Your Mac Keychain |

---

## Signing Configurations in This Project

| Configuration | Style | Identity | Profile |
|---|---|---|---|
| Debug | Automatic | iPhone Developer (auto) | Development (auto, needs registered device) |
| Release | Manual | Apple Distribution | `BlueFunda AI App Store` |

Release is Manual so Archive works without any registered devices.

---

## Exporting Your Certificate for Sharing

When another developer or CI needs to sign builds, they need your `.p12` file.

### Export from Keychain Access

1. Open **Keychain Access** → My Certificates
2. Find **Apple Distribution: BlueFunda, Inc.**
3. Right-click → **Export** → save as `BlueFunda-Distribution.p12`
4. Set a strong password — you'll need it when importing

### Export via command line
```bash
# Find the certificate name
security find-identity -v -p codesigning | grep "Apple Distribution"

# Export to .p12
security export \
  -t identities \
  -f pkcs12 \
  -k ~/Library/Keychains/login.keychain-db \
  -P "your-export-password" \
  -o BlueFunda-Distribution.p12
```

---

## Sharing Options

### Option A: GitHub Actions Secrets (CI/CD — already configured)

The release workflow (`.github/workflows/release-please.yml`) expects these secrets in the repo. Names below match the workflow exactly — a couple of these were previously documented with the wrong name (e.g. `ASC_KEY_ID` vs `APPLE_ASC_KEY_ID`); this table is now the source of truth.

| Secret | Used by | How to generate |
|---|---|---|
| `APPLE_CERTIFICATE` | iOS + macOS | `base64 -i BlueFunda-Distribution.p12 \| pbcopy` |
| `APPLE_CERTIFICATE_PASSWORD` | iOS + macOS | The password you set when exporting |
| `APPLE_KEYCHAIN_PASSWORD` | iOS + macOS | Any string (used for CI temp keychain only) |
| `APPLE_PROVISIONING_PROFILE` | iOS | `base64 -i "BlueFunda AI App Store.mobileprovision" \| pbcopy` |
| `APPLE_MAC_PROVISIONING_PROFILE` | macOS | `base64 -i "BlueFunda AI Mac App Store.mobileprovision" \| pbcopy` — see [APPLE_SETUP.md §7.2](APPLE_SETUP.md#72-create-the-mac-app-store-provisioning-profile) |
| `APPLE_ASC_KEY_ID` | iOS + macOS | App Store Connect → Users & Access → Integrations → Keys |
| `APPLE_ASC_ISSUER_ID` | iOS + macOS | Same page |
| `APPLE_ASC_PRIVATE_KEY` | iOS + macOS | `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `GH_PAT` | release-please | github.com → Settings → Developer Settings → Personal Access Tokens |

Add them at: **github.com/bluefunda/cai-ios → Settings → Secrets and variables → Actions**

The same Apple Distribution certificate and the same App Store Connect API key work for both iOS and macOS — only the provisioning profile differs per platform (Apple issues separate profile types even for the same App ID/cert).

This covers CI. For human developers, use one of the options below.

---

### Option B: Fastlane Match (Recommended for teams)

Match stores encrypted certs and profiles in a private Git repo. Every developer runs one command to get set up.

**One-time setup (done by one person):**
```bash
brew install fastlane
cd /path/to/cai-ios
fastlane match init
# Choose: git
# Repo URL: git@github.com:bluefunda/ios-certificates.git  (create this private repo first)
```

**Generate and store App Store cert + profile:**
```bash
fastlane match appstore --app_identifier com.bluefunda.ai
```

**Generate and store Development cert + profile:**
```bash
fastlane match development --app_identifier com.bluefunda.ai
```

**New developer onboarding (one command):**
```bash
fastlane match appstore --readonly   # install without regenerating
fastlane match development --readonly
```

Match encrypts everything with a passphrase. Share the passphrase via a password manager (1Password, etc.), not in code.

**Advantages over manual sharing:**
- Certs never get emailed around
- One source of truth — no "which .p12 is current?" confusion
- Automatic renewal
- CI uses the same `fastlane match` command with the passphrase as a secret

---

### Option C: HashiCorp Vault (Enterprise)

If your org already runs Vault (e.g. via Kubernetes/gitops), store the `.p12` and `.mobileprovision` as binary secrets:

```bash
vault kv put secret/ios/distribution \
  certificate=@BlueFunda-Distribution.p12 \
  password="your-export-password"

vault kv put secret/ios/profiles \
  appstore=@"BlueFunda AI App Store.mobileprovision"
```

CI retrieves them via the Vault agent or CLI before building. Overkill for a small team but fits naturally if Vault is already in the stack.

---

## Recommendation

| Team size | Recommendation |
|---|---|
| Solo / 1-2 devs | GitHub Actions Secrets for CI + manually share `.p12` via 1Password |
| 3+ devs | Fastlane Match in a private `bluefunda/ios-certificates` repo |
| Enterprise / existing Vault | HashiCorp Vault |

For BlueFunda at current scale: **GitHub Secrets for CI** is already set up.
Add **Fastlane Match** when a second iOS developer joins.

---

## Developer Setup Checklist

New developer joining the iOS project:

- [ ] Added to Apple Developer account (developer.apple.com → People)
- [ ] Added to App Store Connect (appstoreconnect.apple.com → Users and Access)
- [ ] `.p12` certificate imported into Keychain (double-click or `security import`)
- [ ] `BlueFunda AI App Store.mobileprovision` installed (double-click)
- [ ] `BlueFunda AI Mac App Store.mobileprovision` installed if building for Mac (double-click)
- [ ] Xcode → Settings → Accounts → Apple ID added
- [ ] `xcode-select -s /Applications/Xcode.app/Contents/Developer`
- [ ] Can open project, select Release config, see profile without errors
