# Fastlane

All build/sign/upload automation for both iOS and macOS (Mac Catalyst) lives in `fastlane/Fastfile`. CI and local developers use the exact same lanes — there's no separate "CI path" and "local path" for versioning or upload logic.

---

## Setup

```bash
bundle install
```

That's it — no `fastlane match` in this repo (see [CODE_SIGNING.md](CODE_SIGNING.md) for why, and when to introduce it).

---

## Authentication

Every lane calls a `use_api_key` helper in `before_all`:

- If `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_PRIVATE_KEY` are set in the environment (always true in CI — see [CI.md](CI.md)), fastlane authenticates with the App Store Connect API key. No Apple ID, no 2FA prompt.
- If they're **not** set (the normal case for a human running lanes locally), fastlane falls back to your Xcode Apple ID session. You'll get a 2FA prompt the first time, same as manual Xcode uploads.

---

## Lanes

| Lane | What it does |
|---|---|
| `test` | Runs unit tests on an iPhone 16 simulator |
| `bump_version[bump_type:patch\|minor\|major]` | Bumps `MARKETING_VERSION` in `project.pbxproj` locally |
| `ios_beta` | Builds iOS, uploads to TestFlight |
| `ios_upload` | Builds iOS, uploads to App Store Connect — **does not submit for review** |
| `ios_submit` | Submits the most recently uploaded iOS build for review (no rebuild) |
| `mac_beta` | Builds Mac Catalyst, uploads to TestFlight |
| `mac_upload` | Builds Mac Catalyst, uploads to App Store Connect — **does not submit for review** |
| `mac_submit` | Submits the most recently uploaded macOS build for review (no rebuild) |
| `meta` | Pushes App Store metadata only (no binary) |

Run any of them with:

```bash
bundle exec fastlane <lane>
# e.g.
bundle exec fastlane ios_beta
bundle exec fastlane mac_upload
bundle exec fastlane bump_version bump_type:minor
```

**Nothing submits for review automatically.** `ios_submit` / `mac_submit` exist so a human (or a deliberately-triggered, separate CI job — not wired into the default release pipeline) decides when a processed build actually goes to Apple for review. This mirrors the policy that was already in place before this file was rewritten.

To let Apple auto-release immediately after approval instead of waiting for a manual release, set `AUTO_RELEASE=true` before calling `ios_submit`/`mac_submit`:

```bash
AUTO_RELEASE=true bundle exec fastlane ios_submit
```

---

## Versioning — how local and CI stay in sync

Every build-producing lane calls a private `set_version` lane first. It reads two environment variables:

| Env var | Set by | Effect |
|---|---|---|
| `FL_VERSION_NUMBER` | CI, from the release-please tag | Pins `MARKETING_VERSION` to the released version |
| `FL_BUILD_NUMBER` | CI, from `github.run_number` | Pins `CURRENT_PROJECT_VERSION` to a value guaranteed unique per CI run |

Locally, neither is set — `set_version` just increments the build number by 1 from whatever's checked into `project.pbxproj`, leaving `MARKETING_VERSION` alone. This is the same logic path CI uses, just with the two pins omitted, so there's only one versioning code path to reason about (see [RELEASE.md](RELEASE.md#version-numbers) for the full picture, including why the previous split logic caused `MARKETING_VERSION` to drift from what was actually shipped).

---

## Adding a new lane

Keep new lanes inside the existing `platform :ios do ... end` block (it hosts iOS *and* Mac Catalyst lanes — Fastlane platform blocks are just a namespace here, not a real iOS restriction). Reuse `build_ios` / `build_mac` / `set_version` / `use_api_key` rather than duplicating signing or versioning logic.
