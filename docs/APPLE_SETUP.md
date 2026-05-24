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

## Common Errors and Fixes

| Error | Cause | Fix |
|---|---|---|
| "No profiles for 'com.bluefunda.ai'" | Profile not installed locally | Download + double-click `.mobileprovision` from dev portal |
| "No devices from which to generate a profile" | Automatic signing for Release needs registered devices | Use Manual signing for Release config (already set in pbxproj) |
| "Missing CFBundleIconName" | Info.plist missing key | Already added — `CFBundleIconName = AppIcon` |
| "Icon can't contain alpha channel" | Source PNG has transparency | Run `sips` jpeg round-trip to strip alpha |
| "Communication with Apple failed" | `xcode-select` points to CLT not Xcode | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
