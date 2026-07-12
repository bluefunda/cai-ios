# Apple Developer & App Store Connect Setup

One-time setup required before any developer can build or distribute BlueFunda AI.

---

## Prerequisites

- Apple Developer Program membership (paid, $99/year) — bluefunda.com account
- Xcode installed (`/Applications/Xcode.app`)
- `xcode-select` pointing at Xcode, not Command Line Tools:
  ```bash
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  xcodebuild -version   # should print Xcode version, not an error
  ```

---

## 1. App ID Registration

**developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → `+`**

| Field | Value |
|---|---|
| Type | App IDs |
| Bundle ID | `com.bluefunda.ai` (Explicit) |
| Description | `BlueFunda AI` |

**Capabilities to enable:**

| Capability | Reason |
|---|---|
| Push Notifications | Chat reply notifications |
| Associated Domains | Universal Links from `ai.bluefunda.com` |

---

## 2. App Store Connect — Create the App

**appstoreconnect.apple.com → My Apps → `+` → New App**

| Field | Value |
|---|---|
| Platform | iOS |
| Name | BlueFunda AI |
| Primary Language | English (U.S.) |
| Bundle ID | `com.bluefunda.ai` |
| SKU | `bluefunda-ai-ios` |

---

## 3. Distribution Certificate

A **Distribution Certificate** is required to sign any build that leaves your machine (App Store, TestFlight, Ad Hoc).

**In Xcode:**
- Settings → Accounts → select your Apple ID → **Manage Certificates**
- Click `+` → **Apple Distribution**
- Xcode creates the certificate and installs it in your Keychain automatically

Verify it was created:
```bash
security find-identity -v -p codesigning | grep "Apple Distribution"
```

You should see one entry like:
```
1) XXXXXXXX "Apple Distribution: BlueFunda, Inc. (UR7HWT72SR)"
```

---

## 4. App Store Provisioning Profile

A provisioning profile ties your App ID + Distribution Certificate together.
App Store profiles do **not** require registered devices.

**developer.apple.com → Profiles → `+`**

| Field | Value |
|---|---|
| Type | App Store Connect (under Distribution) |
| App ID | `com.bluefunda.ai` |
| Certificate | Select your Apple Distribution cert |
| Profile Name | `BlueFunda AI App Store` |

Download the `.mobileprovision` file and **double-click** it to install.

Verify it's installed:
```bash
ls ~/Library/MobileDevice/Provisioning\ Profiles/ | grep -i bluefunda
```

---

## 5. App Icon Requirements

Apple rejects uploads if the icon has issues. Requirements:
- **1024×1024 px** PNG, no alpha channel, no transparency
- Provided via asset catalog (`AppIcon.appiconset`)
- `CFBundleIconName = AppIcon` in `Info.plist`

The current icon uses the BlueFunda brand mark (Option 2, bright blue).
Source: `~/src/cai/public/images/BlueFunda Assets/5. Linkedin Assets/Option 2/Profile Pic/`

To regenerate if the source changes:
```bash
sips --resampleHeightWidth 1024 1024 "source.png" --out AppIcon-1024.png
# Strip alpha (required by App Store)
sips -s format jpeg AppIcon-1024.png --out /tmp/icon.jpg
sips -s format png /tmp/icon.jpg --out AppIcon-1024.png
sips -g hasAlpha AppIcon-1024.png   # must print: hasAlpha: no
```

---

## 6. URL Scheme Registration (OAuth Callback)

The app uses `cai://auth/callback` for Keycloak OAuth redirect.
This is registered in `CAI/Info.plist` under `CFBundleURLTypes`.

**Keycloak side:** The Keycloak client `cai-ios` must have `cai://auth/callback` listed as a valid redirect URI in each realm (`individual`, `trm`).

---

## 7. macOS (Mac Catalyst) — One-Time Setup

BlueFunda AI ships to Mac as **Mac Catalyst**, not a separate native macOS app — same Xcode target, same bundle ID (`com.bluefunda.ai`), same App Store Connect app record. There is no second app to create. The steps below are the one-time manual portion; everything else (build, sign, upload) is automated the same way as iOS via Fastlane.

### 7.1 App Sandbox — no portal step needed

Mac App Store submissions — including Mac Catalyst — require App Sandbox, but unlike Push Notifications, Sign In with Apple, or Associated Domains, **App Sandbox is not a capability listed under Identifiers → Capabilities on developer.apple.com.** It doesn't require server-side registration on the App ID at all — it's purely an entitlement, validated locally at codesign time. (Native macOS App IDs don't show it in the portal either — it's enabled entirely from Xcode's Signing & Capabilities tab / the entitlements file, and Mac App Store provisioning profiles allow it by default.)

This is already done in the repo: `CAI/CAI-macOS.entitlements` sets `com.apple.security.app-sandbox` and `com.apple.security.network.client`, wired to apply only to the macOS build via `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]` in `project.pbxproj` — iOS keeps using the original `CAI/CAI.entitlements`. Nothing to do on developer.apple.com for this one.

### 7.2 Create the Mac App Store provisioning profile

**developer.apple.com → Profiles → `+`**

| Field | Value |
|---|---|
| Type | Mac App Store Connect (under Distribution) |
| App ID | `com.bluefunda.ai` |
| Certificate | Your existing **Apple Distribution** certificate (the same one used for iOS — Apple's distribution certificate covers both iOS and Mac App Store) |
| Profile Name | `BlueFunda AI Mac App Store` |

This exact name is already referenced in `project.pbxproj` (`PROVISIONING_PROFILE_SPECIFIER[sdk=macosx*]`). If you name it differently, update that build setting to match.

Download the `.mobileprovision` and double-click to install locally, same as the iOS profile.

### 7.3 Enable macOS on the App Store Connect app record

**appstoreconnect.apple.com → My Apps → BlueFunda AI → App Information → Platforms** (or the "+" next to Platforms in the sidebar)

Add **macOS**. This is a one-time manual click Apple doesn't expose over the API — Fastlane/`deliver` cannot add a new platform to an existing app record. Everything after this (metadata, builds, submission) works the same as iOS once the platform exists.

You'll also need, for the macOS version specifically:
- At least one **macOS screenshot** (minimum size 1280×800) before you can submit for review — see `fastlane/screenshots/`.
- App Review notes/demo account can be shared with iOS (`fastlane/metadata/review_information/`) unless the Mac experience needs different reviewer instructions.

### 7.4 First macOS upload

Once 7.1–7.3 are done:

```bash
bundle exec fastlane mac_beta      # TestFlight, sanity check first
bundle exec fastlane mac_upload    # or straight to App Store Connect, no submit
```

Then **mac_submit** (see [FASTLANE.md](FASTLANE.md)) when you're ready for review — submission is never automatic.

---

## Common Errors and Fixes

| Error | Cause | Fix |
|---|---|---|
| "No profiles for 'com.bluefunda.ai'" | Profile not installed locally | Download + double-click `.mobileprovision` from dev portal |
| "No devices from which to generate a profile" | Automatic signing for Release needs registered devices | Use Manual signing for Release config (already set in pbxproj) |
| "Missing CFBundleIconName" | Info.plist missing key | Already added — `CFBundleIconName = AppIcon` |
| "Icon can't contain alpha channel" | Source PNG has transparency | Run `sips` jpeg round-trip to strip alpha |
| "Communication with Apple failed" | `xcode-select` points to CLT not Xcode | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| macOS archive fails: "entitlement not permitted" / sandbox-related | Provisioning profile doesn't match `CAI-macOS.entitlements` | Regenerate the profile in step 7.2 — Mac App Store profiles allow App Sandbox by default, no App ID capability toggle involved |
| macOS build has no app icon in Dock/Cmd+Tab | Old `AppIcon.appiconset` only declared an iOS-scoped image | Already fixed — the asset catalog now includes explicit `mac` idiom renditions (16–512pt, 1x/2x) alongside the iOS universal image |
| Can't select macOS when creating an App Store version in ASC | Platform not yet enabled on the app record | Do step 7.3 — one-time manual click, not automatable |
