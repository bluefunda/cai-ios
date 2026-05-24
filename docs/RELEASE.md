# Build, Test & Release Guide

End-to-end workflow from local development to App Store.

---

## Local Development (Simulator)

No signing required. Works out of the box.

```bash
open /Users/phani/Downloads/src/cai-ios/CAI.xcodeproj
```

- Set destination to any **iPhone Simulator** in the top bar
- **Product → Run** (`⌘R`)

Use this for day-to-day development and UI iteration.

---

## Device Testing (Development Build)

Install directly on your iPhone for real-device feel and performance testing.

### First time — register your device

1. Connect iPhone via USB
2. In Xcode top bar — select your iPhone as destination
3. Xcode prompts: **"Register Device"** — click it
4. This adds your device UDID to developer.apple.com and creates a development profile automatically

### Run on device
- Select your iPhone in the destination picker
- **Product → Run** (`⌘R`)
- First launch: on iPhone go to **Settings → General → VPN & Device Management → trust BlueFunda, Inc.**

Development builds connect to the same backend as production (`https://api.bluefunda.com/ai`).

---

## Validate Before Upload

Before uploading to App Store Connect, run a local validation pass:

1. Set destination to **Any iOS Device (arm64)**
2. **Product → Archive** — wait for build to complete
3. Organizer opens → select the archive → **Validate App**

Validation runs the same checks Apple runs at upload time, without actually uploading. Fix any errors here before proceeding to distribute. Common checks:
- Icon size and alpha channel
- Info.plist required keys
- Entitlements match provisioning profile
- No private API usage

---

## Archive & Upload to App Store Connect

1. Destination: **Any iOS Device (arm64)**
2. **Product → Archive**
3. Organizer → **Distribute App → App Store Connect → Upload**
4. Leave all defaults (include symbols, manage version/build)
5. Click through — Xcode signs, validates, and uploads

The build appears in App Store Connect → TestFlight within ~15 minutes after Apple's automated processing.

---

## TestFlight (Internal Testing — Option 3)

The fastest path to real-device testing without App Store review.

### Internal testers (up to 100, no review required)

1. **appstoreconnect.apple.com → BlueFunda AI → TestFlight**
2. **Internal Testing → `+`** → create a group (e.g. "BlueFunda Team")
3. Add testers by email (must be Apple IDs)
4. Select the build → add to the group
5. Testers receive an email → install **TestFlight** app → accept invite → install BlueFunda AI

### External testers (up to 10,000, requires Beta App Review ~1-2 days)

1. **External Testing → `+`** → create group
2. Add build → Submit for Beta Review
3. After approval, share the public TestFlight link

### Iterating on TestFlight builds

Each new archive upload increments the build number automatically (via `CURRENT_PROJECT_VERSION` in pbxproj, or override during CI via `github.run_number`). Testers get an in-app update notification via TestFlight.

---

## App Store Submission

When ready for public release:

1. **appstoreconnect.apple.com → BlueFunda AI → App Store → `+` version**
2. Fill in:
   - **What's New** — describe the release
   - **Screenshots** — required: 6.7" iPhone (iPhone 15 Pro Max), 12.9" iPad
   - **App Review Information** — demo account credentials if the app requires login
3. Select the TestFlight build you've validated
4. **Submit for Review**

Review typically takes 24-48 hours. Apple may request clarification on:
- Why the app needs the capabilities it declares
- Privacy policy URL (required for apps that collect data)
- Demo account for reviewers to log in

---

## CI/CD — Automated Release

Merging to `main` with conventional commits triggers:

```
push to main
  → release-please creates/updates a Release PR
  → merging the Release PR creates a GitHub Release (tag v1.x.x)
  → ios-deploy job: archive + upload to App Store Connect
  → release-notes job: generate notes via release-foundry
```

### Conventional commit types that trigger a version bump

| Prefix | Version bump | Example |
|---|---|---|
| `fix:` | patch (1.0.x) | `fix: handle 401 on token refresh` |
| `feat:` | minor (1.x.0) | `feat: add conversation search` |
| `feat!:` or `BREAKING CHANGE:` | major (x.0.0) | `feat!: new auth flow` |
| `chore:`, `docs:`, `refactor:` | none | no release created |

### Required GitHub Actions secrets

See [CODE_SIGNING.md](CODE_SIGNING.md#option-a-github-actions-secrets-cicd--already-configured) for the full list and how to generate each value.

---

## Version Numbers

| Field | Location | Meaning |
|---|---|---|
| `MARKETING_VERSION` | `project.pbxproj` / `VERSION` file | User-visible version (e.g. `1.2.0`) — managed by Release Please |
| `CURRENT_PROJECT_VERSION` | `project.pbxproj` | Build number — set to `github.run_number` in CI, increment manually for local uploads |

Apple requires each upload to have a unique `CURRENT_PROJECT_VERSION` within a marketing version.
For local uploads, increment it in Xcode: **Project → Build Settings → Current Project Version**.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Archive disabled (greyed out) | Destination must be **Any iOS Device (arm64)**, not a simulator |
| "No profile matching..." | Download + double-click `.mobileprovision` from dev portal; reopen project |
| "Communication with Apple failed" | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| "Missing icon 152x152" | Icon not in asset catalog or `CFBundleIconName` missing from Info.plist |
| "Alpha channel not allowed" | Strip alpha: `sips` jpeg round-trip (see APPLE_SETUP.md) |
| TestFlight build stuck "Processing" | Normal — Apple takes up to 30 min; do not re-upload |
| Build rejected: "Missing compliance" | Add `ITSAppUsesNonExemptEncryption = false` to Info.plist (already done) |
