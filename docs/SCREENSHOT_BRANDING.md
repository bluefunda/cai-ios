# App Store Screenshot Branding

The main iOS App Store listing's screenshots were raw, uncaptioned simulator output (empty chat state, no device frame, no brand styling) — this pipeline replaces them with a designed set: real device frame, brand-colored background, and a headline caption, built from `BRAND.md`'s actual color/font tokens (not approximations).

---

## How it works

1. **Raw content** — `ScreenshotFixtures.swift` (`#if DEBUG` only) seeds demo conversations; `CAIUITests` drives the app through them via fastlane `snapshot`. See `docs/CUSTOM_PRODUCT_PAGES.md` for how this fixture mechanism works in more detail (it was originally built for Custom Product Pages, which aren't a current priority — but the underlying screenshot generation is shared and still very much in use here).
2. **Curation** — from that raw pool, 4 screens are picked and copied into `fastlane/screenshot_branding/screenshots/en-US/` under names that double as `title.strings`/`keyword.strings` lookup keys: `01-Ask` (general chat), `02-ABAP` (SAP/ABAP capability), `03-History` (conversation sidebar), `04-Persona` (SAP persona tuning in Settings). No pricing/subscription screen — not a good "hero" shot.
3. **Branding** — `bundle exec fastlane ios brand_screenshots` runs `frameit` against that curated folder only, using:
   - `fastlane/screenshot_branding/screenshots/Framefile.json` — background + title/keyword font, size, color per device
   - `fastlane/screenshot_branding/backgrounds/{iphone,ipad}_bg.png` — solid `#FAF9FF` (BRAND.md's `color.brand.hintBlue`) canvases, sized to Apple's exact accepted resolution for each device class (1320×2868 iPhone, 2048×2732 iPad) so the framed+captioned output uploads to the same slot as a raw screenshot would
   - `fastlane/screenshot_branding/fonts/GeneralSans-{Bold,Semibold}.otf` — extracted from `Brand_Guidelines.zip`; General Sans is BRAND.md's canonical marketing typeface (§2.1), used here the same way bluefunda.com already uses it for marketing headlines
   - Title color `#1A305F` (brand navy), keyword/eyebrow color `#1E64E7` (brand blue) — matches BRAND.md's guidance to keep the blue sparing/accent-only

**Important naming note:** the lane is called `brand_screenshots`, not `frame_screenshots` — fastlane has its own built-in action named `frame_screenshots` (aliased as `frameit`), and a lane sharing that exact name gets silently shadowed by the built-in action, which then ignores the `path:` override and frames every PNG under `./fastlane/` (mac screenshots, app icons, the raw CPP pool, all of it). Don't rename it back.

---

## Regenerating

```bash
# 1. Raw content (only needed if you change ScreenshotFixtures' demo data,
#    or want to pick different source screens)
bundle exec fastlane ios screenshots campaign:chat
bundle exec fastlane ios screenshots campaign:code

# 2. Copy whichever 4 raw shots you want into the curated folder, e.g.:
cp "fastlane/screenshots_ios_raw/chat/en-US/iPhone 17 Pro Max-02-Chat.png" \
   "fastlane/screenshot_branding/screenshots/en-US/iPhone 17 Pro Max-01-Ask.png"
# (repeat per device/screen — see title.strings for the current key set)

# 3. Brand them
bundle exec fastlane ios brand_screenshots
```

Output lands as `<original-name>_framed.png` next to the source in `fastlane/screenshot_branding/screenshots/en-US/` — those `_framed.png` files are the ones to upload.

**iPad device note:** the Snapfile uses "iPad Pro 12.9-inch (6th generation)", not a newer 13-inch M4/M5 model — frameit's device database doesn't recognize the newer models' exact pixel dimensions yet ("Unsupported screen size" error), even though the rendered UI is identical (same point-size layout). If frameit adds support later, either device works.

**Known flakiness:** occasionally an iPad screenshot captures with the sidebar mid-animation as a dimmed overlay instead of fully settled (a NavigationSplitView timing quirk, not a real bug — see `CAIUITests/ScreenshotTests.swift`'s `openSidebarIfNeeded`/`dismissKeyboardIfNeeded` comments). If a curated shot looks off, just regenerate that one campaign again and re-copy.

---

## Not yet done

- These framed screenshots are **not wired into `ios_upload`** — that lane still has `skip_screenshots: true` (see `fastlane/Fastfile`), since the live App Store listing currently has its own separately-managed screenshots. Turning this on is a deliberate, separate decision (it changes a public listing) — flag it explicitly before doing so.
- Only `en-US` — no other locales.
- Description/keywords copy (`fastlane/metadata/en-US/`) hasn't been revisited; this pass was visuals-only.
