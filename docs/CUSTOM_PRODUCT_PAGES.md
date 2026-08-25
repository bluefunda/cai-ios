# Custom Product Pages

App Store Connect [Custom Product Pages](https://developer.apple.com/app-store/custom-product-pages) let us market a specific feature with its own screenshots, promotional text, and a shareable URL — without touching the main listing. Two pieces of automation support this, both fastlane-driven:

1. `screenshots` — generates a raw screenshot pool per campaign from the real app (no live backend needed).
2. `cpp_publish` — pushes those screenshots + promo text to a named Custom Product Page via the App Store Connect API.

Neither ever submits anything for review — that stays a manual, deliberate step in App Store Connect, same policy as the rest of this repo's release lanes (see `fastlane/Fastfile`'s header comment).

---

## How screenshots are generated

There's no backend, test account, or real login involved. `CAI/Services/ScreenshotFixtures.swift` (`#if DEBUG` only — never compiled into Release/App Store builds) seeds a fake authenticated session and demo conversations directly, activated by a launch argument:

- `-UITestScreenshots` — skips `AuthManager.restoreSession()`/Keycloak entirely and seeds a demo user instead (`AuthManager.seedForScreenshots`).
- `-UITestCampaign <chat|code>` — picks which demo conversation to seed (`ScreenshotFixtures.demoConversations(for:)`): `chat` is a general-assistant conversation, `code` is an ABAP/SAP-focused one.

`CAIUITests` (a UI Testing Bundle target, added via `scripts/xcode/add_ui_test_target.rb`) drives this through fastlane's `snapshot` tool. `CAIUITests/ScreenshotTests.swift` navigates the seeded app (sidebar → conversation → subscription paywall → settings) using a handful of `accessibilityIdentifier`s added to `ContentView.swift` for exactly this purpose.

Run it:

```bash
bundle exec fastlane ios screenshots campaign:chat
bundle exec fastlane ios screenshots campaign:code
```

Screenshots land in `fastlane/screenshots_ios_raw/<campaign>/<device>/<locale>/*.png` — a separate tree from `fastlane/screenshots/`, which already holds the checked-in **Mac** screenshots `mac_upload` consumes; the two never collide. Devices/languages are configured in `fastlane/Snapfile`.

Both campaigns render through `ChatView` (with different seeded content), not the separate Code-mode SAP object browser — mocking that subsystem's own SAP-connection state was out of scope for this first pass. Extending to real Code-mode screenshots would mean seeding `SAPSystemStore` similarly.

---

## Publishing to a Custom Product Page

```bash
bundle exec fastlane ios cpp_publish \
  name:"Chat Highlight" \
  promotional_text:"Ask anything, get a clear answer." \
  screenshots_dir:"fastlane/screenshots_ios_raw/chat"
```

This finds-or-creates the named page, its version, and its `en-US` localization, sets the promotional text, and uploads any screenshots under `screenshots_dir/<device>/en-US/*.png` that aren't already there (safe to re-run — already-uploaded files are skipped by name). It's implemented as a fastlane action (`fastlane/actions/upload_custom_product_page.rb`) backed by a small hand-rolled App Store Connect API client (`fastlane/lib/asc_client.rb`), since fastlane's own `deliver` has no Custom Product Page support. The client reuses the exact same `ASC_KEY_ID`/`ASC_ISSUER_ID`/`ASC_PRIVATE_KEY` env vars (and GitHub secrets `APPLE_ASC_*`) that `fastlane/Fastfile`'s `use_api_key` lane already relies on — no new secrets.

**`screenshotDisplayType` note:** `upload_custom_product_page.rb`'s `DISPLAY_TYPE_BY_DEVICE` map is best-known-current at time of writing. If App Store Connect rejects a value, its error body lists the accepted enum values directly — update the map with whatever it reports; the run is idempotent, so re-running after a fix picks up where it left off.

### After publishing

Nothing here submits for review. Once the page's content looks right in App Store Connect:

1. **Apps → CAI → App Store → Custom Product Pages** → open the page.
2. **Add for Review** → attach to a new or existing submission → **Submit for Review**.
3. This does not require a new build — the currently-live app version keeps shipping while the page is reviewed. Once approved, the page's URL (`apps.apple.com/app/id.../?ppid=...`) is ready to use in campaigns, and future edits to an already-approved page auto-publish after re-review without changing the URL.
