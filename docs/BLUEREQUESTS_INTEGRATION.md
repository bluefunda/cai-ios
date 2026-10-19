# BlueRequests in cai-ios: UI design principles

Status: proposal, 2026-10-18
Scope: bring the trm-ios feature set (BlueRequests: change requests, projects, releases,
teams, messages) into cai-ios, and redesign the sidebar, chat history and gen-AI navigation
so one app holds both.
Companion: [`prompts/bluerequests-integration.md`](prompts/bluerequests-integration.md), the
Claude Code (Sonnet) prompt that implements this design.

---

## 0. Ground truth (what exists today)

| | cai-ios (BlueFunda AI) | trm-ios (BlueRequests) |
|---|---|---|
| Code | `main`, 98 Swift files, App Store 2.12.0 | `bluefunda/trm-ios` @ `origin/feat/initial-import` (`main` is an empty commit) |
| Realm / client | `individual` / `cai-ios`, redirect `cai://auth/callback` | `trm` / `requests-ios` (never registered) |
| API base | `https://api.bluefunda.com/ai` (cai-gw → cai-bff) | `https://api.bluefunda.com/requests` (trm-gw → trm-backend-go) |
| Shell | `AppShell`: 2-col `NavigationSplitView` (iPad/Mac) or ZStack drawer (iPhone); `AppMode` = chat / code | Same shell pattern; `AppSection` = requests / messages / projects / teams / releases |
| Sidebar | Brand, conversation list (search, pinned, date groups, paging), a lone "Code" row, Upgrade pill, profile menu | Brand, five nav rows with an unread badge, profile menu |
| Design system | `BF*` tokens, **adaptive light/dark** (`Color(lightHex:darkHex:)`, `surfaceCanvas/Sidebar/Raised/Sunken`) | Older fork of the same tokens, not adaptive |

trm-ios features to carry over: CR list (list + grid, status filter, pagination via
`ChangeRequestFilter.limit`), CR detail (fields, stage, activity timeline, tabs, edit,
archive/unarchive, files upload/download), comments (HTML body, attachments, post), new CR
(request type, severity, project, platforms), projects list + detail + filter, releases
(read-only, grouped by planned date), teams, unread-count poller, profile (notification
toggle). Messages is still a placeholder in trm-ios. The web app's Git and admin screens
(manage teams, configurations, request templates, user management) stay out of scope.

### Tenancy: the backend gap (this blocks shipping, not building)

The plan: users sign in once to the `individual` realm, and membership in the Keycloak
**organization `trm`** unlocks BlueRequests.

- cai-ios already asks for the `organization` scope and parses the claim
  (`AuthManager.firstOrganization`, `User.organization`), but it keeps **only the first org**.
- cai-bff already handles this: `SharedOrgRealms` (cai-bff#166) substitutes the org slug for
  the realm when the token comes from a shared realm, and cai-gw forwards the
  `organization` claim as `X-Organization`.
- **trm-backend-go does not.** `jwtMiddleware.go` takes the tenant from the last path
  segment of `iss`, so an `individual` token resolves to the `individual` DB, not `trm`.
  trm-gw also validates against the `trm` realm and calls Keycloak admin at
  `/admin/realms/trm/...` for users, teams and groups.

Backend work needed before release (tracked separately; not part of the iOS prompt):
1. trm-gw: accept `individual`-realm JWTs (JWKS/issuer) on `/requests/*` and forward
   `organization` → `X-Organization` (copy the cai-gw `jwt_bff.tmpl` mapping).
2. trm-backend-go: port cai-bff#166 so that `realm ∈ SharedOrgRealms && org claim present ⇒
   tenant = org`. The org slug `trm` matches the old realm name, so `tenantDBMap["trm"]`
   keeps working.
3. trm-backend-go: aim the Keycloak admin calls (users, groups, teams) at org members in
   `individual`, not at `/admin/realms/trm`.
4. Role mapping: decide where trm `admin` lives now (an org role or a client role) so
   `User.isAdmin` still means something.

Until then the iOS work runs behind a feature flag with fixture-backed services, so the UI
can ship to TestFlight early without depending on the backend.

---

## 1. Design principles

### P1. One identity, many workspaces. Never a second login.
There is one `AuthManager`, one realm (`individual`) and one token. BlueRequests is an
**entitlement** that comes from the token's `organization` claim, not a separate sign-in.
The app never asks for a realm and never shows "Sign in to BlueRequests". The client never
claims a tenant (no `X-Realm: trm` header). The gateway works the tenant out from the
verified token.

### P2. Spaces, not modes. The sidebar says where you are.
Today `AppMode` (chat/code) is a hidden toggle behind one sidebar row. Replace it with an
explicit **Space → Destination** model:

```
Space        Destinations
─────────    ──────────────────────────────────────────────
Assistant    Chats · Code · Files · Agents
Requests     Inbox · Requests · Projects · Releases · Teams      (only if org "trm")
```

A **Space switcher** (a 2-segment control) sits at the top of the sidebar. It appears only
when the user has more than one space, so a personal-only user sees exactly what they see
today, minus the clutter. Each space keeps its own last destination, so switching back lands
you where you left off. Persist this with `@AppStorage`, as `app_mode` does now.

### P3. The sidebar has three layers, always in the same order.
```
┌──────────────────────────────┐
│ BlueFunda            [⊟]     │  1. Header: brand + collapse toggle (+ new-item button on iPhone)
│ ┌────────────┬─────────────┐ │
│ │ Assistant  │  Requests ³ │ │  2. Space switcher (badge = unread count from the other space)
│ └────────────┴─────────────┘ │
│  💬 Chats                    │  3a. Destinations for the active space (fixed, short)
│  </> Code                    │
│  🗂 Files                    │
│  🧩 Agents                   │
│ ───────────────────────────  │
│  🔍 Search conversations     │  3b. Context list for the active destination (scrolls)
│  Pinned                      │      Chats → conversation history
│   · S/4 upgrade checklist    │      Requests → recently viewed CRs + quick filters
│  Today                       │      Projects → recently viewed projects
│   · Transport error TR 4012  │      Code → connected SAP systems
│  Yesterday …                 │
│ ───────────────────────────  │
│ ✨ Upgrade to Pro         ›  │  4. Footer: upgrade pill (individual free only)
│ (P) Phani · trm      ···     │     + profile row with org chip
└──────────────────────────────┘
```
Rules: destinations never scroll away (layer 3a is fixed). Only 3b scrolls. The footer is
always pinned. In the profile row the org chip shows the active org (`trm`) next to the name
and email, so people can always see whose data they are looking at.

### P4. Chat history is a first-class list, not a sidebar afterthought.
Keep everything that already works in `SidebarConversationList` (server search with a 300 ms
debounce, paging, Pinned / Today / Yesterday / This Week / Older, pin from context menu),
and add:
- **Row anatomy:** title (1 line, `sidebarItem`), then a meta line (`sidebarMeta`, secondary)
  with a relative time plus a persona or connector glyph when the chat used one (SAP, GitHub,
  Sales Tracker). A selected row gets a `primaryTint` capsule. Hovering on Mac shows trailing
  `···` (rename, pin, share, delete).
- **Group headers in sentence case** ("Pinned", "Today"): `sidebarMeta` semibold, secondary
  colour, no `.textCase(.uppercase)`. Today's headers are uppercase; change them.
- **Swipe actions on iPhone:** leading = pin, trailing = delete (with confirmation).
- **"New chat" is a single home:** a toolbar button on iPad/Mac and a header button in the
  iPhone drawer, as today. ⌘N on Mac.
- **Empty states with a call to action:** "No conversations yet → Start a chat". Search with
  no hits shows the query back and suggests clearing it.
- **Linked conversations:** a chat started from a change request (see P8) shows a `doc.text`
  glyph and the CR number in its meta line, and appears in that CR's "AI" tab.

### P5. Gen-AI tools are destinations, not buried buttons.
| Destination | What it is today | What changes |
|---|---|---|
| Chats | default mode | unchanged content; history moves into layer 3b |
| Code | sidebar row that flips `AppMode` | becomes a peer destination; its 3b list shows SAP systems (`SAPSystemStore`), and "Manage systems" moves there from the server-rack toolbar button |
| Files | `StorageView` sheet, unreachable from the sidebar | becomes a destination; it gets the full detail column instead of a sheet |
| Agents | "Agents" tab inside the composer attach sheet + `SettingsView+Agents` | becomes a destination listing MCP connectors (SAP, GitHub, Sales Tracker) with connect status; the composer keeps its quick picker |

The composer (`ModeModelPicker`, `PersonaComposerControl`, attach sheet) stays as it is.
These destinations are for browsing and managing; the composer is for using.

### P6. Requests screens follow the list → detail grammar, at native density.
- **Regular width (iPad/Mac):** the space's detail column holds a `NavigationStack`, and a CR
  list row pushes the detail. Keep trm-ios's rule that only one section's stack is mounted at
  a time, with view-model boxes owned by the shell so state survives switching sections.
  Don't add a third split column in v1; cai-ios#256 shows how fragile split-view visibility is.
- **List row (CR):** first line: the request number (Inter semibold, `.monospacedDigit()`,
  secondary colour, not a monospace font) and the status pill on the trailing edge. Second
  line: title (2 lines max). Third line: the stage rail (P13) on the left, then the
  requester's avatar and a relative date on the right. Project name is a small tinted label
  above the title only when the list isn't already filtered to one project. The row is 64 pt
  minimum, uses the full width, and has no chevron on Mac. Don't build meta strings by
  joining fields with " · "; use separate visual groups.
- **Status is a token, not an ad-hoc colour.** Add `BFColor.status*` (draft, submitted,
  inReview, approved, rejected, deployed, closed), each a `lightHex/darkHex` pair, and use
  them for every status pill, filter chip and timeline dot.
- **Toolbar is per destination**, built in the shell's single `ToolbarItemGroup`:
  Requests → filter, list/grid toggle, `+ New`; Projects → filter; Chats → attach, new chat;
  Code → systems. Only one destination's toolbar exists at a time (Mac Catalyst toolbars are
  window-level).
- **Detail screen:** a header card (number, title, status pill, stage progress "Stage 2 of 4"),
  then a segmented control: Details · Activity · Comments · Files · **AI**. Editing and
  archiving live in a `···` menu. Destructive actions confirm.

### P7. One design system: cai-ios's.
trm-ios's `BF*` files are an older, non-adaptive fork. **Delete them on import.** Every
ported view uses cai-ios tokens (`surfaceCanvas`, `surfaceSidebar`, `surfaceRaised`,
`surfaceSunken`, `primaryTint`, `BFFont.sidebar*`, `BFSpacing`, `BFRadius`). Check every new
screen in light and dark mode on iPhone, iPad and Mac Catalyst. Use `BFDropdownMenu`, not
`Menu`, inside the sidebar column (cai-ios#292/#293). Add `.bfPointerHover()` to every
tappable element on Mac.

### P8. AI and Requests should feed each other. That is the point of one app.
- **Ask AI about this request:** a CR detail action that opens a new chat with a context chip
  ("REQ-1234 · Transport fails in QA") holding the title, description, status, platforms and
  the last 10 timeline entries. This is client-side prompt assembly with no backend change.
  The chat is linked to the CR (stored locally: `conversationId ↔ crId`).
- **Create a request from an answer:** an assistant message's action menu offers
  "Create change request…", which opens `NewChangeRequestView` with the title prefilled from
  the conversation title and the description from the message's markdown.
- **AI tab on CR detail:** lists the conversations linked to this CR, plus "New chat about
  this request".
- Later: `REQ-\d+` in chat text becomes a tappable link (`MessageFileLinks` already does this
  for files).

### P9. Badges and attention live in one place.
`UnreadCountPoller` (trm-ios) runs only while the Requests entitlement is active and the app
is in the foreground. Its count shows on the Space switcher's "Requests" segment, on the
"Inbox" destination row, and on the app icon badge only if notifications are authorized.
Never show a badge for a space the user can't open.

### P10. Mac and keyboard are first-class.
| Shortcut | Action |
|---|---|
| ⌘N | New chat (Assistant) / New request (Requests) |
| ⌘1 … ⌘5 | Destinations of the active space |
| ⌃⌘1 / ⌃⌘2 | Switch space |
| ⌘F | Focus the sidebar search |
| ⌘R | Refresh the current list |

Add them with `.keyboardShortcut` on the existing buttons, plus `CommandMenu`s in
`CAIApp.swift` for Catalyst.

### P11. Graceful degradation, never a dead end.
- Entitlement missing → the Requests space doesn't exist (no greyed-out tease).
- Entitlement present, backend not ready (401/403/5xx from `/requests`) → an inline,
  space-scoped error card ("BlueRequests is unavailable right now · Retry"). It must
  **never** call `authManager.expireSession()`, because a trm-gw failure must not sign the
  user out of their chats.
- Feature flag `bf_feature_requests` (in `BFFeatureFlags`, default **off** until the backend
  lands) and a `-bf_requests_fixtures YES` launch argument backed by trm-ios's
  `ScreenshotFixtures`.

### P12. Screenshots and accessibility.
- Every new row and button gets an `accessibilityIdentifier` (`requests.crRow.<id>`,
  `sidebar.space.requests` …) for UI tests and fastlane snapshots.
- Status pills carry text, not just colour. Dynamic Type works up to XXL in list rows
  (meta lines can wrap; titles don't truncate below 1 line).
- New App Store screenshot set: "Your change requests, with AI beside them" (see
  `docs/SCREENSHOT_BRANDING.md`).

### P13. Visual direction: the brand palette, used with discipline, and one bold element.
The palette is already fixed by `BRAND.md`, so this is about how to apply it, not what to
choose.

| Role | Token | Light | Dark | Rule |
|---|---|---|---|---|
| Canvas | `surfaceCanvas` | `#FFFFFF` | `#131314` | 60%: the page |
| Structure | `secondary` (Deep Blue) | `#1A305F` | `#D9E2F3` (new adaptive pair) | headings, the selected space segment, stage-rail track |
| Tint | `brand.hintBlue` / `lightBlue` | `#FAF9FF` / `#D9E2F3` | `surfaceSidebar` / `#1B2440` | sidebar wash, selection |
| Accent | `primary` (Happy Blue) | `#1E64E7` | unchanged (`BFColor.primary`) | **about 4%**: only tappable things, focus, unread dots |
| Status | `tertiary.light.*` fill + `tertiary.deep.*` text | per BRAND.md §1.5 | swap fill and text, darken the fill | see the mapping below |

Status mapping (the *only* place tertiary colours appear in product UI): draft = neutral
grey, submitted = light blue, in review / in progress = orange, approved = green,
rejected = red, deployed / transported = purple, closed / archived = neutral at 60% opacity.
Pills are capsule-shaped with 11 pt semibold text in sentence case, never colour alone.

**The one bold element: the stage rail.** A change request's journey (`stage` of
`totalStages`, typically DEV → QAS → PRD in the SAP transport landscape) is drawn as a
row of short connected segments. Completed segments are filled Deep Blue, the current one
takes its status colour, and future ones are the hairline colour. It appears full-size
(with stage names, when the API has them) in the CR detail header, and as a 4 pt-tall,
48 pt-wide mini rail in every list row and in the Ask-AI context chip. It is the single
visual signature of the Requests space, and everything around it stays quiet: no card
shadows on list rows, no gradients, hairline separators only. When stage data is missing,
draw nothing rather than a placeholder rail.

**Type:** Inter throughout (`BFFont` existing scale). Use `.monospacedDigit()` for request
numbers, counts and dates in lists so columns line up. The only monospace face stays in code
blocks and ABAP source. Don't add a display face to these screens. A CR detail title is
`BFFont.h5`, and list titles are `rowSemibold`.

**Motion:** only in response to the user. Switching space cross-fades the sidebar's layers
3a and 3b (0.2 s, `BFMotion`). The stage rail animates once, when a status change you made
succeeds. Respect Reduce Motion.

**Copy:** sentence case, plain verbs, and the same action name throughout a flow. The button
says "New request", the sheet title says "New request" and the toast says "Request created".
Use "Ask AI about this request", not "AI Insights". Errors say what happened and what to do
next ("Couldn't load requests. Check your connection and try again."), and never apologise.
Empty states invite action: "No requests match these filters", then "Clear filters".

---

## 2. Screen inventory

| # | Screen | Source | Notes |
|---|---|---|---|
| 1 | Sidebar (rebuilt) | cai `SidebarContent` + `SidebarDrawer` merged | One shared `SidebarView` with an `onNavigate` closure; iPhone wraps it in a drawer |
| 2 | Space switcher | new | 2-segment control, selected segment filled Deep Blue; hidden for single-space users |
| 3 | Chats + history | cai | history moves into layer 3b; adds row meta + swipe |
| 4 | Code | cai `CodeContent` | 3b = SAP systems |
| 5 | Files | cai `StorageView` | from sheet to destination |
| 6 | Agents | cai `SettingsView+Agents` + attach sheet | read/manage connectors |
| 7 | Requests list / grid / filter | trm | restyled with tokens; quick filters in 3b |
| 8 | Request detail (+ AI tab) | trm + new | P6, P8 |
| 9 | New / Edit request | trm | prefill entry point from chat |
| 10 | Projects list / detail / filter | trm | |
| 11 | Releases | trm | read-only |
| 12 | Teams | trm | |
| 13 | Inbox (Messages) | trm placeholder | v1 = unread activity feed if an endpoint exists, otherwise an honest "coming soon" |
| 14 | Settings → BlueRequests pane | trm `SettingsView` profile part | notification toggle, department, team; only when entitled |

## 3. Phasing (each phase is one PR)

1. **Foundation:** multi-org parsing, `Workspace` and entitlement, `RequestsAPIClient`,
   feature flag, fixtures, status tokens. No visible change while the flag is off.
2. **Shell and sidebar redesign:** spaces, destinations, chat-history polish, Files and Agents
   as destinations. Visible to everyone and works for personal-only users.
3. **Requests port:** all trm-ios screens behind the flag.
4. **Bridges:** Ask AI, create-from-answer, AI tab, keyboard shortcuts, screenshots.
