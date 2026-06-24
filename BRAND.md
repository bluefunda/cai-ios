# BlueFunda AI — Canonical Brand Token Specification

> **Audit sources (in priority order)**
> 1. `~/src/cai` — web app (shipped product, primary authority)
> 2. `~/src/bluefunda.com` — marketing website
> 3. `Brand_Guidelines.zip` — official brand book (font files, logo variants, icon pack)
>
> Generated: 2026-06-24. Read-only audit — neither repo was modified.

---

## 1. Color Tokens

### 1.1 Primary (Brand Blue)

| Token | Hex | Source | Usage |
|-------|-----|--------|-------|
| `color.primary` | `#1E64E7` | cai, logo SVG | CTA buttons, links, selected states, active tabs, unread indicators |
| `color.primary.hover` | `#1D4ED8` | cai (dark-mode btn var) | Button hover state |
| `color.primary.pressed` | `#1A56D4` | extrapolated from `#0d4fd4` in bluefunda.com | Button pressed / active |
| `color.primary.tint` | `#EEF2FF` | cai `--table-row-hover`, `--selected-message-bg`, `--tab-hover` (`#EDF0FF`) | Row hover, selection highlight, focused surfaces |
| `color.primary.subtle` | `#F2F6FF` | cai `--hover-background`, `--release-metadata-hover-background` | Subtle hover fills |

### 1.2 Secondary / Navy (Brand Deep Blue)

| Token | Hex | Source | Usage |
|-------|-----|--------|-------|
| `color.secondary` | `#1A305F` | logo SVG ("funda" letterforms), bluefunda.com `--secondary-heading-text-black`, `--team-details-text` | Section headings, dark brand accents |
| `color.secondary.dark` | `#111E38` | cai `--dark-text`, `--header-bold-text` | Bold heading text in the app |
| `color.secondary.sidebar` | `#1B1E37` | cai `--sidebar-bg` | Main nav sidebar background |
| `color.secondary.admin` | `#030D60` | cai `--sidebar-bg-admin` | Admin-mode sidebar variant |
| `color.secondary.border` | `#424660` | cai `--border-color` | Sidebar/dark-surface borders |

### 1.3 Brand Book Secondary Colors

Defined in §2.2 of the brand book as "unique to BlueFunda" and "synonymous with the brand." Used primarily as backgrounds.

| Token | Hex | Source | Usage |
|-------|-----|--------|-------|
| `color.brand.lightBlue` | `#D9E2F3` | Brand book §2.2 | Background tints, section washes, subtle highlights |
| `color.brand.hintBlue` | `#FAF9FF` | Brand book §2.2 | Near-white brand-tinted background (10% usage proportion) |

### 1.4 Brand Color Proportions

From brand book §2.4 — these are the intended **usage ratios** for any brand communication:

| Color | Token | Hex | Proportion | Role |
|-------|-------|-----|------------|------|
| White | `color.neutral.0` | `#FFFFFF` | **60%** | Background of choice — dominant surface |
| Deep Blue | `color.secondary` | `#1A305F` | **20%** | Structure, text, heavy fills |
| Hint of Blue | `color.brand.hintBlue` | `#FAF9FF` | **10%** | Background tint |
| Light Blue | `color.brand.lightBlue` | `#D9E2F3` | **6%** | Secondary backgrounds |
| Happy Blue | `color.primary` | `#1E64E7` | **4%** | Accent only — CTAs, interactions |

> Key implication for iOS: `#1E64E7` should appear sparingly. It's a high-signal accent color, not a fill. Reserve it for tappable elements, active states, and brand moments.

### 1.5 Tertiary Palette (Semantic / Illustration)

From brand book §2.3 — intended for illustrations, photography tinting, and product semantics. Each "Happy" color has a matching light background and deep shadow variant with the same contrast ratio.

| Token | Hex | Role |
|-------|-----|------|
| `color.tertiary.happy.blue` | `#1E64E7` | (same as primary) |
| `color.tertiary.happy.red` | `#E71E1E` | Error / danger (matches `color.error`) |
| `color.tertiary.happy.orange` | `#E77E1E` | Caution / in-progress |
| `color.tertiary.happy.mustard` | `#E7D31E` | Warning / notice |
| `color.tertiary.happy.green` | `#1EE77A` | Success |
| `color.tertiary.happy.purple` | `#8F1EE7` | Special / premium |
| `color.tertiary.happy.pink` | `#E71E97` | Highlight / featured |
| `color.tertiary.light.red` | `#F3D9D9` | Error background tint |
| `color.tertiary.light.orange` | `#F3E4D9` | Caution background tint |
| `color.tertiary.light.mustard` | `#F3F0D9` | Warning background tint |
| `color.tertiary.light.green` | `#D9F3E3` | Success background tint |
| `color.tertiary.light.blue` | `#D9E2F3` | Info background tint (= `color.brand.lightBlue`) |
| `color.tertiary.light.purple` | `#E9D9F3` | Premium background tint |
| `color.tertiary.light.pink` | `#F3D9E9` | Featured background tint |
| `color.tertiary.deep.red` | `#5F1A1A` | Error shadow / border |
| `color.tertiary.deep.orange` | `#5F3B1A` | Caution shadow |
| `color.tertiary.deep.mustard` | `#5F581A` | Warning shadow |
| `color.tertiary.deep.green` | `#1A5F36` | Success shadow |
| `color.tertiary.deep.purple` | `#411A5F` | Premium shadow |
| `color.tertiary.deep.pink` | `#5F1A43` | Featured shadow |

### 1.6 Accent / Highlight

| Token | Hex | Source | Usage |
|-------|-----|--------|-------|
| `color.accent.blue` | `#1361F5` | bluefunda.com `--btn-bg-blue`, marketing CTA buttons | Marketing CTA (not in brand book — see conflicts §9) |
| `color.accent.indigo` | `#2563EB` | cai `--primary-btn` (input area), top-header CTA | Input submit button, header actions |
| `color.accent.purple.from` | `#6366F1` | cai navbar gradient start | Gradient accent (AI agent icon fill) |
| `color.accent.purple.to` | `#8B5CF6` | cai navbar gradient end | Gradient accent (AI agent icon fill) |

### 1.7 Neutral / Surface

| Token | Hex | Source | Usage |
|-------|-----|--------|-------|
| `color.neutral.0` | `#FFFFFF` | everywhere | Page background, card surfaces |
| `color.neutral.50` | `#F9FAFB` | cai `--select-background`, `--grid-card-bg`, modern nav bg | Input/grid backgrounds |
| `color.neutral.100` | `#F3F4F6` | cai `--input-bg` (dark mode baseline), header search bg | Search/input fills |
| `color.neutral.200` | `#E5E7EB` | cai nav borders, dividers | Dividers, subtle borders |
| `color.neutral.300` | `#D1D5DB` | cai scrollbar thumb, progress incomplete | Scrollbars, inactive progress |
| `color.neutral.400` | `#9CA3AF` | cai `--placeholder-text` | Placeholder text |
| `color.neutral.500` | `#6B7280` | cai nav icon color, feature card descriptions | Body text light |
| `color.neutral.600` | `#4B5563` | — | (available, not directly observed) |
| `color.neutral.700` | `#374151` | cai nav text, header text | Nav labels, secondary text |
| `color.neutral.900` | `#1C1F25` | bluefunda.com submenu text | High-contrast dark text |
| `color.neutral.950` | `#000000` | cai `--dark-black` | Pure black (rare) |

**Brand off-white surfaces:**

| Token | Hex | Source | Usage |
|-------|-----|--------|-------|
| `color.surface.offWhite` | `#F9F9F9` | bluefunda.com `--off-white` | Marketing page bg |
| `color.surface.tableHeader` | `#FAFAFA` | cai `--table-header-background`, `--grid-card-bg` | Table headers, grid cards |
| `color.surface.blueWash` | `#F8F9FF` | cai pricing card bg | Light-blue-tinted card surface |
| `color.surface.chatReceiver` | `#F5F5F5` | cai `--message-text-receiver-background` | Received chat bubble |
| `color.surface.chatSender` | `#E8EBFA` | cai `--message-text-sender-background` | Sent chat bubble |

### 1.8 Semantic — Status

| Token | Hex | Source | Usage |
|-------|-----|--------|-------|
| `color.success` | `#56C04C` | cai `--success-btn-bg`, `--progress-bar-completion-bg` | Success actions, progress complete |
| `color.success.bg` | `#DFF9D3` | cai `--complete-tag-bg` | "Complete" status badge bg |
| `color.success.border` | `#B6DFA2` | cai `--complete-tag-border` | "Complete" status badge border |
| `color.warning` | `#F7AA16` | cai `--severity-low-bg` | Low severity / caution |
| `color.warning.bg` | `#FFF3CA` | cai `--inprogress-tag-bg` | "In Progress" badge bg |
| `color.warning.border` | `#EBD99D` | cai `--inprogress-tag-border` | "In Progress" badge border |
| `color.error` | `#EE1B1B` | cai `--severity-high-bg` | Error / high-severity |
| `color.error.delete` | `#E72A1E` | cai `--delete-btn-bg` | Destructive action button |
| `color.error.danger` | `#C2260E` | cai `--danger-btn-color` | Danger text label |
| `color.info` | `#1E64E7` | (reuses primary) | Info state shares brand blue |
| `color.info.bg` | `#DBEFF5` | cai `--planned-tag-bg` | "Planned" badge bg |
| `color.info.border` | `#92D0E2` | cai `--planned-tag-border` | "Planned" badge border |

### 1.9 Semantic — Text

| Token | Hex | Source | Usage |
|-------|-----|--------|-------|
| `color.text.primary` | `#1F252D` | cai `--heading-text` | App heading text |
| `color.text.heading` | `#1E1E1E` | bluefunda.com `--heading-text-black` | Marketing heading text |
| `color.text.body` | `#1E293B` | bluefunda.com blog body | Long-form body text |
| `color.text.secondary` | `#333333` | cai form labels, login labels | Form fields, labels |
| `color.text.tertiary` | `#5A5A5A` | cai `--app-text-light` | Lighter secondary text |
| `color.text.placeholder` | `#9CA3AF` | cai `--placeholder-text` | Input placeholders |
| `color.text.disabled` | `#929292` | cai `--light-text-color` | Disabled/inactive labels |
| `color.text.muted` | `#7D7D7D` | bluefunda.com `--subheader-text` | Marketing subheadings |
| `color.text.inverse` | `#FFFFFF` | everywhere | Text on dark/colored surfaces |
| `color.text.link` | `#1E64E7` | reuses primary | Hyperlinks |
| `color.text.chatMessage` | `#242424` | cai `--message-text-color` | Chat message text |

---

## 2. Typography

### 2.1 Font Families

| Token | Value | Weights available | Source |
|-------|-------|-------------------|--------|
| `font.family.display` | `General Sans` | Extralight (200), Light (300), Regular (400), Medium (500), Semibold (600), Bold (700) + italic variants | Brand book OTF files; bluefunda.com body + headings |
| `font.family.body` | `Inter` | Variable (100–900) | cai app (woff + variable TTF shipped in `/public/fonts`) |
| `font.family.body.alt` | `DM Sans` | Variable (100–900) | cai app (variable TTF shipped; used in newer components) |
| `font.family.mono` | `Roboto Mono` | 400 | bluefunda.com code blocks (via Google Fonts) |

**Usage split:**
- **Marketing site** (`bluefunda.com`): `General Sans` for both body and headings (`general-sans` / `general-sans-semi` face names)
- **Web app** (`cai`): `Inter` for UI chrome; `DM Sans` emerging in newer components; `monospace` for code blocks
- **Brand book canonical**: `General Sans` is the primary brand typeface (the only OTF family in the brand book)

### 2.2 Type Scale

Observed sizes across both repos — mapped to semantic roles:

| Token | Size | Line-height | Weight | Role |
|-------|------|-------------|--------|------|
| `font.size.display` | 50px (clamp 28–50px) | 1.2 | 700 | Marketing hero / max heading |
| `font.size.h1` | 48px | 1.2 | 700–800 | Page titles (app + marketing) |
| `font.size.h2` | 38px | 52px (≈1.37) | 700 | Section headings (marketing) |
| `font.size.h2.app` | 32px | — | 700 | App section headings |
| `font.size.h3` | 28px | 1.2 | 600–700 | Subsection headings |
| `font.size.h4` | 24px | — | 600 | Card titles |
| `font.size.h5` | 20px | — | 700–800 | Pricing plan names |
| `font.size.bodyLarge` | 20px | 32px (1.6) | 400 | Marketing body / intros |
| `font.size.bodyMedium` | 18px | — | 400–500 | Login CTA button text, body paragraphs |
| `font.size.body` | 16px | 1.5–1.8 | 400 | Default body text |
| `font.size.bodySmall` | 14px | — | 400–500 | Secondary body, nav labels, table cells |
| `font.size.caption` | 13px | — | 600 | Form labels (all-caps letter-spaced) |
| `font.size.micro` | 12px | — | 400 | Timestamps, metadata, micro labels |
| `font.size.code` | 14px (0.875rem) | 1.6 | 400 | Code blocks |

**Label style:** Form labels use `13px / font-weight 600 / letter-spacing 0.07em` (caps-adjacent treatment without forced uppercase).

### 2.3 Role Mapping

| Role | Family | Size token | Weight |
|------|--------|------------|--------|
| Marketing hero heading | General Sans | `display` | 700 |
| App screen heading | Inter / DM Sans | `h1`–`h3` | 600–700 |
| Body copy (marketing) | General Sans | `bodyLarge`–`body` | 400 |
| Body copy (app) | Inter | `body`–`bodySmall` | 400 |
| Nav label | Inter / DM Sans | `bodySmall` | 500 |
| Form label | Inter | `caption` | 600 |
| Button text | Inter | `bodyMedium`–`bodySmall` | 500–700 |
| Code / terminal | Roboto Mono | `code` | 400 |
| Timestamp / meta | Inter | `micro` | 400 |

---

## 3. Spacing, Radius, and Elevation

### 3.1 Spacing Scale

No explicit named scale token system was found in either repo; spacing appears as literal values. The observed set forms an 8-point grid:

| Token | Value | Observed usage |
|-------|-------|----------------|
| `spacing.1` | 4px | Tight padding, small gaps |
| `spacing.2` | 8px | Icon margins, compact padding |
| `spacing.3` | 12px | Between-element gaps |
| `spacing.4` | 16px | Section padding base, container horizontal padding |
| `spacing.5` | 20px | Form padding (tablet) |
| `spacing.6` | 24px | Settings section padding, dept gap |
| `spacing.8` | 32px | Login form group spacing |
| `spacing.10` | 40px | Login fields top margin |
| `spacing.12` | 48px | Login form top offset |
| `spacing.14` | 56px | Top header height |
| `spacing.16` | 64px | Top header height (desktop) |
| `spacing.20` | 80px | Section top padding |

**Nav widths:** Expanded = 256px (`16rem`), Collapsed = 64px (`4rem`).
**Container max-width:** 1280px (`80rem`).

### 3.2 Corner Radius

| Token | Value | Source / usage |
|-------|-------|----------------|
| `radius.sm` | 4px | Chips, small badges, minimal rounding |
| `radius.md` | 6px | Blockquotes, small buttons (bluefunda.com) |
| `radius.lg` | 8px | Buttons, cards, inputs, modals (most common) |
| `radius.xl` | 10px–12px | Nav item hover, feature cards, some dropdowns |
| `radius.full` | 9999px | Pill buttons, avatar rings |

`8px` (`radius.lg`) is the dominant value — 16 occurrences vs 4 for `4px` across the audited files.

### 3.3 Elevation / Shadow

| Token | Value | Usage |
|-------|-------|-------|
| `shadow.sm` | `0 2px 4px rgba(0,0,0,0.10)` | Cards (resting) |
| `shadow.md` | `0 2px 8px rgba(0,0,0,0.10)` | Modals, dropdowns |
| `shadow.lg` | `0 4px 12px rgba(19,97,245,0.30)` | Primary CTA button shadow (brand-tinted blue) |
| `shadow.lg.hover` | `0 4px 12px rgba(19,97,245,0.40)` | CTA button hover elevation |
| `shadow.xl` | `0 8px 32px rgba(0,0,0,0.12), 0 2px 8px rgba(0,0,0,0.06)` | Nav dropdown submenu |
| `shadow.overlay` | `rgba(0,0,0,0.40)` | Modal backdrops, blur overlays |

---

## 4. Motion

| Token | Value | Context |
|-------|-------|---------|
| `motion.duration.fast` | `150ms` | App UI transitions (nav collapse, button hover, chevron rotate) — the dominant app value |
| `motion.duration.normal` | `200ms` | Dropdown appear/disappear, opacity fades |
| `motion.duration.slow` | `300ms` | Card hover lift, pricing transitions, marketing CTA |
| `motion.duration.xslow` | `500ms` | Marketing hero animations (carousel, nav expansions) |
| `motion.duration.entrance` | `1000ms` | Hero image fade-in-from-right animation |
| `motion.easing.default` | `ease` | General shorthand across both repos |
| `motion.easing.inOut` | `ease-in-out` | Header scroll shadow, hero image |
| `motion.easing.entrance` | `ease-out` | Hero entrance animation |

**Pattern:** The app uses `0.15s ease` universally for interactive state changes (hover, focus, active). Marketing uses `0.2s–0.5s` for larger, more dramatic transitions.

---

## 5. Iconography

### 5.1 In-code icon sets

| Library | Usage context |
|---------|--------------|
| `@mui/icons-material` v5 | Primary icon library in the CAI web app. MUI icons are filled-style Material Design icons. |
| Custom SVGs (public/images/) | Application-specific icons: sidebar logout, send button, timeline, attachment controls. |
| Lucide / Feather / Heroicons | Not found in either repo. |

### 5.2 Brand icon pack (from Brand_Guidelines.zip)

The zip includes a `Coolicons`-based SVG set organized in 20 categories:

- `arrow`, `attention`, `basic`, `brand`, `calendar`, `chart`, `communication`, `device`, `edit`, `experimental`, `file`, `grid`, `home`, `media`, `menu`, `misc`, `notification`, `system`, `user`

**Style:** Line/outline stroke icons (Coolicons set). These are distinct from the filled MUI icons currently used in the app.

**Sizing:** No explicit icon size scale found; observed sizes in CSS: 16px, 18px, 20px, 24px, 28px, 60px (feature illustrations).

**Recommended token:**

| Token | Value | Role |
|-------|-------|------|
| `icon.size.sm` | 16px | Inline / compact |
| `icon.size.md` | 20px | Standard UI icon |
| `icon.size.lg` | 24px | Nav / emphasis icon |
| `icon.size.xl` | 28–32px | Section icon |
| `icon.size.illustration` | 48–64px | Feature/empty-state illustrations |

---

## 6. Logo Assets

### 6.1 Brand colors in logo

The logo wordmark uses exactly two colors:
- `#1E64E7` — "BLUe" (B, L, U, e letterforms + bracket/arrow mark)
- `#1A305F` — "funda" (f, u, n, d, a letterforms + closing accent mark)

### 6.2 Logo variants (from Brand_Guidelines.zip)

**Main Logo (full wordmark "BlueFunda"):**
| Variant file | Background | Usage |
|---|---|---|
| `Original Logo for White Background.svg` | White | Primary/default |
| `Logo for White Background.svg` | White | Alternate white bg |
| `Logo for Deep Blue Background.svg` | Deep blue | On dark navy surfaces |
| `Logo for Happy Blue Background.svg` | Brand blue | On primary-blue surfaces |
| `Logo for Black Background.svg` | Black | Dark theme / footer |

**Short Logo (abbreviated form):**
Same five background variants as Main Logo.

**Symbol (mark only — "B" letterform):**
Same five background variants.

**Arrow mark (standalone accent element):**
5 color variants: Black, Deep Blue, Happy Blue, Light Blue, White.

**In-repo logo files:**
| Path | Dimensions | Usage |
|------|-----------|-------|
| `cai/public/images/common/full-name-logo.svg` | 1568×256 | Full wordmark, general use |
| `cai/public/images/leftNavbar/company-logo.svg` | 22×24 | Collapsed sidebar (B mark only, white text on dark bg) |
| `cai/public/images/login/company-logo.svg` | 291×41 | Login screen (full wordmark) |
| `cai/src/styles/login/style.scss` | 192×32px CSS | Login form logo container |
| `bluefunda.com/static/images/logos/logo.svg` | 157×26 | Marketing nav header |

### 6.3 Logo Rules (from Brand Book §1)

**Clearspace:** Equal to the cap-height of the "B" letterform on all sides. Nothing may break this boundary.

**Minimum display sizes (§1.5):**
| Size | Context |
|------|---------|
| 124pt | Desktop / large print |
| 64pt | Standard app use |
| 32pt | Compact / tab bar |
| 16pt | Minimum — favicon/icon level |

**Color-background rules (§1.4):**
- Default: color logo on white or light backgrounds
- B&W only: white logo on dark/black backgrounds; black (`#1E1E1E`) logo on white
- The brand book's "black" is `#1E1E1E`, not `#000000`

**Prohibitions (§1.6):**
- Do not add drop shadows or any effects to the logo
- Do not stretch, rotate, or manipulate the logo
- Do not change the position of elements within the logo
- Do not use General Sans in other weights/typefaces for the wordmark
- Do not pair the logo with icons that could be confused as logos
- Do not place on backgrounds that reduce visibility
- Restrict color use to guideline-specified colors only (§2.5)

**Copy rules (§1.6):**
- Always write as **BlueFunda** — no space between "Blue" and "Funda"
- Always capitalize both "B" and "F"

### 6.4 Arrow Symbol Rules (from Brand Book §4.1)

The brand arrow mark is a standalone graphic element — not just the logo piece.

- It represents Forward, Movement, Dynamic, Direction, Drive, Motivation
- Can be used in multiple rotations/orientations for graphic compositions
- **Never use more than once on a single graphic** (exception: tiled patterns per §4.2–4.3)
- Pattern variants: large (backdrop/highlight) and small (grid-fill)
- Only use colors from the Main and Secondary palette (`#1E64E7`, `#1A305F`, `#D9E2F3`, `#FAF9FF`, `#FFFFFF`)

---

## 7. Voice & Visual Personality

**Summary:** Clean, credible enterprise AI — confident but not flashy.

- **Color personality:** Deep navy (`#1A305F`) anchors authority and trust; vivid blue (`#1E64E7`) signals technology and forward motion. The ratio is ~60/40 navy-to-blue in the logo itself, which visually codes as "serious platform with an energetic accent" rather than "startup blue everywhere."
- **Typography personality:** `General Sans` (brand canonical) reads as modern geometric sans — cleaner than Roboto, warmer than Inter. Its use in marketing while `Inter` runs the app is a practical split: Inter has better screen hinting at small sizes. The brand aspires to General Sans everywhere.
- **Layout personality:** Generous whitespace, 8px grid, strong use of card-based surfaces with consistent `8px` radius. Not a dense-data enterprise tool — closer to modern SaaS (Notion/Linear aesthetic) than SAP or Salesforce.
- **Motion personality:** App interactions snap at `150ms` (fast, tightly controlled). Marketing moves at `300–500ms` (deliberate, weighty). The difference reinforces "our product is snappy" vs "our brand is trustworthy."
- **Copy tone (inferred):** From section headings and CTA labels seen in source: direct, action-oriented, benefit-led ("Future of AI", "Validate. Scale."). No playful puns or emoji. Enterprise-professional without being dry.

---

## 8. Conflict Table

| Element | `cai` (app) | `bluefunda.com` (marketing) | Recommendation | Rationale |
|---------|-------------|-----------------------------|----------------|-----------|
| Primary blue | `#1E64E7` | `#1361F5` | **`#1E64E7`** | Confirmed by brand book §2.1 as "Happy Blue" — the canonical primary. `#1361F5` is not in the brand book at all; it's an undocumented marketing drift that should be corrected. |
| Button hover | `#1D4ED8` | `#0D4FD4` | **`#1D4ED8`** | Closer to Tailwind's blue-700 step from the primary; `#0D4FD4` is too dark at small sizes. |
| Body font (app) | `Inter` | `General Sans` | **`General Sans` canonical; `Inter` acceptable fallback for app UI** | Brand book ships only General Sans; marketing already uses it for body. Migrate app to General Sans over time. |
| Heading color | `#1F252D` (app `--heading-text`) | `#1E1E1E` (marketing `--heading-text-black`) | **`#1F252D`** | Near-identical; the app value has a very slight blue tint that aligns better with the navy brand secondary. |
| Sidebar color | `#1B1E37` (user sidebar) / `#030D60` (admin) | — (not applicable) | Keep both; name them `sidebar.user` and `sidebar.admin` | These serve two distinct roles and should remain separate tokens. |
| Border radius (common) | Mostly `8px` | Mostly `8px`, some `6px` in pricing | **`8px`** | 8px is overwhelmingly dominant in both repos. |
| Corner radius (card) | `8–12px` | `10–12px` (feature cards) | **`12px` for cards, `8px` for inputs/buttons** | Slight differentiation between interactive controls and content containers is intentional. |
| Shadow tint | Neutral (`rgba(0,0,0,0.10)`) | Brand-blue (`rgba(19,97,245,0.30)`) | **Brand-blue shadow for primary CTA buttons only; neutral for all other elevation** | The blue shadow is a strong brand signal on CTAs; applying it everywhere would feel heavy. |
| Nav transition | `0.15s ease` | `0.2s–0.5s ease` | **`0.15s ease` for interactive states; `0.3s ease` for marketing-style entrance animations** | App needs the faster value for perceived responsiveness. |

---

## 9. Open Questions

1. **General Sans licensing for iOS:** The brand book ships `.otf` files — confirm whether the font license covers app binary distribution, or if a web/app font license needs to be purchased before embedding in the iOS bundle.

2. **Dark mode color set:** The CAI app has a `[data-theme='dark']` block for a handful of input-area variables (`#1F2937` background, `#3B82F6` primary). A complete dark palette (surfaces, text, borders) is not defined. Is dark mode in scope for the iOS app?

3. **Coolicons vs MUI icons:** The brand book ships Coolicons (outline/stroke style); the app uses MUI Material icons (filled style). These are visually inconsistent. Decision needed: migrate the app to Coolicons (outline) or accept dual icon languages per context?

4. **`#2857C8` — AI banner blue:** The marketing site's "new-ai-banner" uses `#2857C8` (a medium slate-blue) as a full-bleed section background. This isn't represented in any token. Is this a third brand blue or a one-off?

5. **`#667EEA` / `#764BA2` gradient:** Used in `_bluefunda-ai.scss` for the "BlueFunda-AI section" on the marketing site. This purple-to-indigo gradient doesn't appear in the app. Is it intentional AI-product branding, or a layout placeholder?

6. **Spacing system:** Neither repo uses a named spacing token system (e.g., `$space-4`, `--space-md`). The iOS SwiftUI implementation should adopt a formal named scale — should that be strict 4pt, 8pt, or something else?

7. ~~**Logo safe-zone and minimum size:**~~ **RESOLVED.** Brand book §1.2 defines clearspace = cap-height of "B". Minimum sizes: 16pt, 32pt, 64pt, 124pt. Full prohibition list in §6.3 above.

8. **Accent gradient usage rules:** The indigo-to-purple gradient (`#6366F1` → `#8B5CF6`) appears in the AI agent icon in the sidebar. Is this gradient intended as a broader AI-feature accent, or is it component-specific?

9. **Typography heading color:** Marketing uses `#0F1F5C` (very deep navy, close to `#1A305F`) for blog `h1`–`h4`. The app uses `#1F252D` (near-black). Confirm the canonical "heading text" color for the iOS app.

10. **Status badge colors in iOS:** The web app has rich status badge tokens (planned/in-progress/complete/blocked). Which of these concepts exist in the iOS app feature set, and should they all be included in the iOS token system?

---

## 10. Login UX Pointers

> Source: `cai/src/components/login/index.js` + `cai/src/styles/login/style.scss` (redesigned in v1.1.0).
> This section translates the shipped web login pattern into guidance for the iOS equivalent.

### 10.1 Layout Structure

The web login is a **two-panel split**:

```
┌─────────────────────────┬──────────────────┐
│                         │   Logo (192×32)  │
│   Hero image            │                  │
│   (60% width,           │   Email          │
│    object-fit: cover)   │   Password       │
│                         │   Forgot pwd     │
│                         │   Remember me    │
│                         │                  │
│                         │   [  Login  ]    │
│                         │                  │
│                         │   Register now   │
└─────────────────────────┴──────────────────┘
     60vw                       40vw
```

**iOS mapping:**
- **iPhone:** Single-column. Drop the hero image entirely (or use it as a full-bleed background with the form card floated over it). Form panel is the primary content.
- **iPad:** Recreate the split — hero image fills the leading pane, form in the trailing pane at ~40% width. Use `HStack` with fixed trailing width or `NavigationSplitView`.
- **Mobile (≤768px web):** Hero moves *below* the form (`order: 2`). On iOS this is the opposite of the desktop — iOS should match the web mobile behavior: form on top, hero image optional/below.

### 10.2 Component Inventory

| Element | Web spec | iOS equivalent |
|---------|----------|----------------|
| Logo | 192×32pt, `company-logo.svg` (full wordmark) | `Image("full-name-logo")`, frame height 32pt |
| Email field | Plain `<input>`, border `#BBBBBB`, full-width | `TextField` with `.textContentType(.emailAddress)`, `.keyboardType(.emailAddress)` |
| Password field | Plain `<input type=password>` | `SecureField` with show/hide toggle |
| Field label | 13pt / weight 600 / letter-spacing 0.07em / `#333333` | `.caption` + `.fontWeight(.semibold)` + `.kerning(0.91)` (= 13 × 0.07), color `color.text.secondary` |
| Input border | `1px solid #BBBBBB` | `.overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex:"#BBBBBB"), lineWidth: 1))` |
| Forgot password | Inline below password, 15pt, `#1E64E7` | `Button` styled as `.plain` with `color.primary` foreground, trailing-aligned |
| Remember me | Checkbox + 14pt label | `Toggle` with `.toggleStyle(.checkmark)` or native iOS switch; 14pt / weight 400 |
| Primary CTA | Full-width, 56pt height, `#1E64E7` fill, `radius.lg` (8pt), 18pt/500, white text | `Button` with `buttonStyle(.blueFundaPrimary)` — see §11.3 |
| Register link | 17pt, centered, `#333333` + `#1E64E7` inline link | `Text` with `AttributedString` or `Button` inline in a `HStack` |
| Spacing: logo → fields | 48pt top margin | `.padding(.top, 48)` |
| Spacing: between field groups | 32pt | `.padding(.top, 32)` |

### 10.3 Primary Button Style (SwiftUI)

```swift
// Token mapping from §1–§3
struct BlueFundaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color(hex: "#1E64E7"))     // color.primary
            .cornerRadius(8)                        // radius.lg
            .shadow(
                color: Color(hex: "#1361F5").opacity(0.30),  // shadow.lg
                radius: 6, x: 0, y: 4
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
```

### 10.4 Form Label Style

Web uses all-caps rendering implicitly via letter-spacing without `text-transform: uppercase`. iOS should be consistent:

```swift
Text("EMAIL ID")
    .font(.system(size: 13, weight: .semibold))
    .kerning(0.91)          // 0.07em × 13pt
    .foregroundColor(Color(hex: "#333333"))  // color.text.secondary
```

### 10.5 UX Notes & Gaps

- **No social sign-in in code:** The v1.1.0 commit message mentions "social sign-in" but the shipped component (`login/index.js`) contains only email/password fields. Social buttons are not implemented on web yet — iOS should not add them until the web ships a reference.
- **No validation states:** The web form has no inline error states, loading states, or field-level validation in the current code. iOS should define these using `color.error` (`#EE1B1B`) and `color.error.bg` for field borders/messages — these are in the token set even though the web login doesn't use them yet.
- **Hero image asset:** `/images/login/login-left-bg.svg` exists in the web repo but is not included in the iOS repo. If using on iPad, export as PDF/SVG and add to the asset catalog.
- **Auto-fill:** Add `.textContentType(.emailAddress)` and `.textContentType(.password)` to enable iOS Keychain auto-fill — the web form lacks this equivalent.
- **Accessibility:** Field labels are visually above inputs but not semantically linked (`<label for>` is absent in the web code). In SwiftUI, use `.accessibilityLabel("Email")` on the `TextField` to avoid the same gap.
