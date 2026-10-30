# Claude Code prompt: BlueRequests integration (run with Sonnet)

Usage, from the cai-ios repo root:

```bash
claude --model sonnet
# then paste everything below the line, or:
claude --model sonnet "$(sed -n '/^---8<---$/,$p' docs/prompts/bluerequests-integration.md | tail -n +2)"
```

Run **one phase per session**: say "Do Phase 1" and so on. Each phase ends with a PR, and
you review it before starting the next.

---8<---
You are implementing the BlueRequests integration in **cai-ios** (SwiftUI, iOS 17+, iPadOS
and Mac Catalyst, MVVM, no third-party dependencies). Read these first and treat them as the
spec. If they disagree with this prompt, the design doc wins:

1. `docs/BLUEREQUESTS_INTEGRATION.md`: design principles P1–P13, screen inventory, phasing.
2. `docs/ARCHITECTURE.md`, `BRAND.md`, `CAI/DesignSystem/*`.
3. `CAI/Views/ContentView.swift` (`AppShell`, `SidebarContent`, `SidebarDrawer`),
   `CAI/Views/SidebarConversationList.swift`, `CAI/Views/Code/CodeView.swift` (`AppMode`),
   `CAI/Services/AuthManager.swift`, `CAI/Utilities/APIClient.swift`,
   `CAI/Utilities/BFFeatureFlags.swift`.

The source app to port is **trm-ios**, at `../trm-ios` on branch `origin/feat/initial-import`
(its `main` is empty). Read it with `git -C ../trm-ios show origin/feat/initial-import:<path>`
and list it with `git -C ../trm-ios ls-tree -r --name-only origin/feat/initial-import`.
**Never check out, commit to or modify trm-ios.**

If the `frontend-design` skill is available, load it before building any new view, and
follow P13 of the design doc for palette, type, the stage rail and copy.

## Ground rules (every phase)

- **One identity.** Use cai-ios's existing `AuthManager` (realm `individual`, client
  `cai-ios`). Do NOT port trm-ios's `AuthManager`, `LoginView`, `KeychainStore`, `requests-ios`
  client ID, `requests://` scheme or `trm` realm. Don't add an `X-Realm` header for
  BlueRequests calls. The tenant comes from the token's `organization` claim on the server.
- **One design system.** Do NOT port trm-ios's `TRM/DesignSystem/*`. Map every token the
  ported code uses onto cai-ios's `BF*` tokens, which are adaptive light/dark. Add any missing
  token to cai-ios's files using the `Color(lightHex:darkHex:)` pattern.
- **Name collisions.** cai-ios already has `User`, `AppConfig`, `APIClient`, `APIError`,
  `SettingsView`, `LoginView`, `LoadingView`, `SafariView`, `ContentView`, `AppShell`,
  `SidebarContent`, `KeychainStore`, `ScreenshotFixtures`. Ported code goes under
  `CAI/Requests/{Models,Services,ViewModels,Views}`. Rename trm types that collide or are too
  generic: `Project` → `RQProject`, `Comment` → `RQComment`, `Attachment` → `RQAttachment`,
  `Team` → `RQTeam`, `Release` → `RQRelease`, trm `APIClient` → `RequestsAPIClient`,
  `AppSection` → `RequestsDestination`, trm `SettingsView` → `RequestsSettingsSection`,
  trm `ScreenshotFixtures` → `RequestsFixtures`. Reuse cai's `User` and `SafariView`.
- **Xcode project.** `CAI.xcodeproj` uses classic groups, not folder sync, so new files must
  be added to `project.pbxproj` under the CAI target (tests under CAITests). Use the
  `xcodeproj` Ruby gem, which fastlane already provides (`bundle exec ruby -e ...`), rather
  than hand-editing the pbxproj. Verify the build afterwards.
- **Errors are scoped.** A 401/403/5xx from the Requests API must never call
  `authManager.expireSession()` or `logout()`, so a trm-gw failure can't sign users out of
  chat. Surface it as an inline error card in the Requests space with a Retry button.
- **Keep the existing behaviour.** Don't regress what cai-ios#253/#254/#256/#257/#292/#293/
  #335/#370 fixed (their comments are in the code). Keep `.doubleColumn` column visibility,
  `.balanced` style, the custom `SidebarToggleButton` on Catalyst, `BFDropdownMenu` inside
  the sidebar, explicit `environmentObject` re-injection into sheets, conversation paging and
  search debounce. Read each of those comments before changing the code around it.
- **Match local style.** Follow the comment density, `// MARK:` usage and naming of the
  surrounding code. Add `accessibilityIdentifier`s to new interactive elements
  (`sidebar.space.requests`, `requests.crRow.<id>`, …).
- **Verify each phase.** On macOS, run
  `xcodebuild -project CAI.xcodeproj -scheme CAI -destination 'platform=iOS Simulator,name=iPhone 16' build test`
  and also build for Mac Catalyst (`-destination 'platform=macOS,variant=Mac Catalyst'`).
  If you can't run xcodebuild (for example on Linux), say so explicitly in the PR and list
  what you couldn't verify. Never claim it builds without running it.
- **Branching and PRs.** For each phase, branch from `main` as
  `feat/bluerequests-phase-<n>-<slug>`, use conventional commits (release-please is in use),
  open a PR with `gh pr create`, and **stop**. Don't start the next phase.

## Phase 1: Foundation (no visible change while the flag is off)

1. **Multi-org parsing.** In `AuthManager`, add `User.organizations: [String]` beside the
   existing `organization` (keep that as `organizations.first` for compatibility). Parse the
   Keycloak `organization` claim in all three shapes: a string, an array of strings, and an
   object whose keys are the org aliases (Keycloak sets this when org attributes or IDs are
   mapped). Extend `firstOrganization` and its tests (`AuthTokenRefreshTests` or a new
   `OrganizationClaimTests`).
2. **Workspace / entitlement.** Add `enum AppSpace { case assistant, requests }` and an
   `@MainActor final class WorkspaceStore: ObservableObject` holding `availableSpaces`
   (computed from `organizations.contains(AppConfig.requestsOrgAlias)` with
   `requestsOrgAlias = "trm"`, and from the feature flag), plus the persisted `activeSpace`
   and per-space last destination (`@AppStorage`-backed). Inject it in `CAIApp.swift` next to
   the existing environment objects.
3. **Config and flags.** `AppConfig.requestsBaseURL = "https://api.bluefunda.com/requests"`
   plus trm's request timeout and retry constants. In `BFFeatureFlags`, add `requestsEnabled`
   (key `bf_feature_requests`, **default false**) and `requestsFixtures` (key
   `bf_requests_fixtures`, default false), in the same style as the existing flags.
4. **`RequestsAPIClient`.** Port trm-ios `TRM/Utilities/APIClient.swift` and
   `AsyncCache.swift`, keeping its retry and backoff behaviour and the `Access-Token` +
   `Authorization: Bearer` headers (trm-backend-go reads `Access-Token`). Its token provider
   is `authManager.validAccessToken()`. Give it its own error type that maps 401/403 to a
   non-fatal `.requestsUnavailable`.
5. **Models and services.** Port `TRM/Models/APIModels.swift` and every `TRM/Services/*`
   service protocol and implementation except `AuthManager` and `Environment`, applying the
   renames above. Keep trm's defensive decoding and its doc comments about unconfirmed
   fields. Port `ScreenshotFixtures` as `RequestsFixtures` and add fixture-backed
   implementations of each service protocol, selected when `requestsFixtures` is on.
   Port `UnreadCountPoller` so it only polls while `requests` is an available space and the
   app is active.
6. **Tokens.** Add the P13 tokens to `BFColors.swift`: `secondaryAdaptive`, the
   `status*` fill/text pairs mapped from BRAND.md §1.5, and `hairline` if missing.
   Add a `ChangeRequestStatus.style` (fill, text, label) mapping in one place.
7. **Tests.** Port `TRMTests/APIModelsTests.swift`, `ChangeRequestListViewModelTests.swift`,
   `ReleasesListViewModelTests.swift` and `MockServices.swift` into CAITests (renamed), plus
   new tests for org-claim parsing and `WorkspaceStore.availableSpaces`.

PR title: `feat(requests): foundation for BlueRequests in cai-ios (flagged off)`.

## Phase 2: Shell and sidebar redesign (visible to everyone)

Implement P2, P3, P4, P5, P7, P10 (Assistant shortcuts only) and P13 copy and motion rules.

1. Replace `AppMode` with `AssistantDestination { chats, code, files, agents }` and
   `RequestsDestination { inbox, requests, projects, releases, teams }`. Migrate the old
   `app_mode` `@AppStorage` value (`code` → `.code`).
2. Merge `SidebarContent` and `SidebarDrawer` into one `SidebarView` with the layered
   structure from P3: header, space switcher (hidden when `availableSpaces.count == 1`),
   fixed destination rows, a scrolling context list, and a pinned footer (upgrade pill +
   profile row with the org chip). iPhone wraps it in the existing drawer and keeps the
   drawer's close-then-select sequencing (`completionCriteria: .logicallyComplete`). iPad/Mac
   keeps the persistent split view.
3. Context list (layer 3b) per destination: Chats → `SidebarConversationList` (unchanged
   behaviour, with sentence-case headers, row meta line, iPhone swipe pin/delete, Mac hover
   `···`); Code → SAP systems from `SAPSystemStore`, with a "Manage systems" row; Files → none;
   Agents → none.
4. Files becomes a destination rendering `StorageView` in the detail column. Remove the
   storage sheet path, but keep `StorageView` working inside a sheet if anything else still
   presents it. Agents becomes a destination listing MCP connectors and their connection state,
   reusing the views behind `SettingsView+Agents` and the composer's Agents tab (factor the
   shared list out; don't duplicate it).
5. Toolbar per destination, in the shell's single `ToolbarItemGroup`. Chats: attach and new
   chat. Code: systems. Files and Agents: none.
6. Keyboard shortcuts: ⌘N for new chat, ⌘1–⌘4 for Assistant destinations, ⌘F to focus sidebar
   search.
7. A personal-only user (no `trm` org, or the flag off) must see no Space switcher and no
   Requests UI at all. Add a UI test or snapshot-style unit test for that.

PR title: `feat(shell): spaces and destinations sidebar, chat history polish`.

## Phase 3: Requests port (behind `bf_feature_requests`)

Implement P6, P9, P11, P12 and the P13 stage rail.

1. Port the trm-ios views into `CAI/Requests/Views`: `ChangeRequestListView`,
   `ChangeRequestGridView`, `ChangeRequestFilterSheet`, `ChangeRequestDetailView`,
   `EditChangeRequestView`, `NewChangeRequestView`, `CommentThreadView`,
   `ProjectsListView`, `ProjectDetailView`, `ProjectFilterSheet`, `ReleasesListView`,
   `TeamsListView`, `ListScreenHeader`, `ShareSheetPresenter`, `ToolbarComponents`, and
   their view models. Keep trm's view-model boxes, owned by the shell so state survives
   switching destinations, and keep its "only one NavigationStack mounted" rule (read the
   comment in trm's `AppShell.content`).
2. Restyle everything with cai tokens: the CR row anatomy from P6, status pills from the
   `ChangeRequestStatus.style` mapping, and the `StageRail` view (full and mini sizes; it
   renders nothing when `stage`/`totalStages` are nil). Use `BFDropdownMenu` for menus inside
   the sidebar, and add `.bfPointerHover()` to tappables.
3. CR detail: a header card (number, title, status pill, full stage rail), then a segmented
   control with Details, Activity, Comments and Files (AI is added in Phase 4). Put Edit and
   Archive in a `···` menu, and confirm destructive actions.
4. Context list for the Requests space: quick filters (All, Mine, Needs my review if the API
   supports it; otherwise only status filters), then "Recently viewed" (last 8 CRs, stored
   locally via `@AppStorage` JSON or `LocalFileStore`).
5. Inbox: if trm-ios's `NotificationsService` exposes an activity list, render it. Otherwise
   show an empty state: "Activity from your requests will show up here." Don't invent an
   endpoint.
6. Toolbar: Requests → filter, list/grid toggle, `New request`; Projects → filter.
   ⌘N creates a new request when the Requests space is active. Use ⌘1–⌘5 for its
   destinations, ⌃⌘1/⌃⌘2 to switch space, and ⌘R to refresh.
7. Unread badge on the Requests segment and the Inbox row (P9).
8. Settings: add a BlueRequests section (notification toggle, department, team from trm's
   profile service), shown only when the space is available.
9. Error card (P11) for Requests API failures, with Retry.
10. Test with `-bf_feature_requests YES -bf_requests_fixtures YES` in iPhone, iPad and Mac
    Catalyst, light and dark. Add view-model tests for the list, detail and new-request flows
    using the fixture services.

PR title: `feat(requests): port BlueRequests screens into cai-ios (flagged)`.

## Phase 4: AI ↔ Requests bridges

Implement P8 and the rest of P10/P12.

1. **Ask AI about this request:** a CR detail action that switches to the Assistant space,
   starts a new conversation and attaches a context chip (number, title, mini stage rail).
   The prompt context is title, description, status, platforms and the last 10 timeline
   entries, sent as part of the first message the same way `ST22PromptBuilder` assembles
   context (read it first and mirror the approach). Store the `conversationId ↔ crId` link
   locally.
2. **Create a request from an answer:** add "Create change request…" to the assistant
   message action menu, shown only when the Requests space is available. It opens
   `NewChangeRequestView` prefilled with the title from the conversation title and the
   description from the message markdown converted to plain text.
3. **AI tab on CR detail:** lists linked conversations (tap to open in the Assistant space)
   and has a "New chat about this request" button.
4. Linked conversations show a `doc.text` glyph and the CR number in their sidebar row meta.
5. Add `CommandMenu`s in `CAIApp.swift` for the Catalyst menu bar, covering every shortcut.
6. Add fastlane snapshot scenes for the Requests list, CR detail and Ask-AI chat, using
   fixtures (see `docs/SCREENSHOT_BRANDING.md` and the existing `ScreenshotFixtures`).

PR title: `feat(requests): ask AI about requests, create requests from answers`.

## Out of scope (don't build)

Backend changes (trm-gw issuer and JWKS, trm-backend-go org→tenant substitution, Keycloak
admin calls); the trm web app's Git, manage-teams, configurations, request templates and
user-management screens; push notifications; a multi-org workspace picker (design the
`WorkspaceStore` seam, but with one org there is nothing to pick).

If anything in the trm-ios code or the API is ambiguous, keep trm-ios's current behaviour
and its "unconfirmed" comments, and list the question in the PR description rather than
guessing.
