# SAP Engagement Backlog Plan (Draft — not yet created as GitHub issues)

Goal: engagement + habit + shareability for BlueFunda AI's distribution to SAP
technical folks (ABAP, BASIS), functional consultants (FI, FI-CA, IS-U), and
leaders (SI founders).

Grounding: `ChatRequest` (`CAI/Services/ChatServiceProtocol.swift:97`) already
has an `agentName` field with an existing "abaper" persona-routing precedent,
plus a multi-select MCP assistant picker (#166/#171/#172) and an in-flight
router-intent debug surface (#173). Epic 1 builds on that instead of
reinventing it. "Daily tip" is intentionally folded into the existing
Contextual Tip Engine backlog (#155–161, blocked on `bluefunda/tip-catalog`
Phase 0) rather than duplicated.

## Labels to create
| Label | Purpose |
|---|---|
| `epic` | marks epic-tracking issues |
| `abap` | persona |
| `basis` | persona |
| `fi` | persona |
| `is-u` | persona |
| `leader` | persona |
| `feature` | type |
| `chore` | type |
| `p0` | priority |
| `p1` | priority |
| `p2` | priority |

Existing labels (`bug`, `enhancement`, `documentation`, etc.) are left untouched.

## Milestones
- **v1 — Immediate Wins**: the 3 P0 items (persona-tagged chat, ST22 dump
  decoder, one-tap shareable answers) + their epics
- **v1.1 — Persona Depth**: Technical/Functional/Leader toolkit P1 items,
  persona-based onboarding, feedback loop
- **v1.2 — Engagement & Growth**: remaining P2 toolkit items, Tip Engine push
  wrapper, sharing/streaks

---

## Epic 1 — SAP-aware AI chat (anchor feature)
Epic body links #155–161 (Tip Engine) and #171–173 (multi-assistant routing)
as related work, not duplicated.

| # | Title | Labels | Effort |
|---|---|---|---|
| 1.1 | Add persona selector and send it as chat context | `feature`,`p0` | M |
| 1.2 | Persona-specific empty-state prompt suggestions | `feature`,`p1` | S |
| 1.3 | Thumbs up/down feedback tagged with persona | `feature`,`p1` | S |
| 1.4 | "Re-answer with a different persona lens" action | `feature`,`p2` | S |

**1.1 Add persona selector and send it as chat context** — p0, M
Story: As an ABAP developer, I want the assistant to know my SAP specialty so
answers use the right terminology and depth without me re-explaining every time.
AC:
- Settings (and first-run onboarding, see 5.2) lets the user pick a home
  persona: ABAP / BASIS / FI / IS-U / Leader / General
- Selection is sent on `ChatRequest` (reusing/extending the existing
  `agentName` field, mirroring the "abaper" precedent) so cai-llm-router can
  route/tune
- Persists across launches (`SAPSystemStore`/UserDefaults)
- Switching persona applies to the next message, no restart

**1.2 Persona-specific empty-state prompt suggestions** — p1, S
Story: As a new FI-CA consultant, I want example prompts for my domain on
first open so I know what the assistant is good for.
AC:
- Empty chat state shows 3–4 example prompts drawn from the selected persona
- Tapping a suggestion sends it as the first message
- Suggestion sets are data-driven, not hardcoded per view

**1.3 Thumbs up/down feedback tagged with persona** — p1, S
Story: As a leader piloting this with my team, I want a lightweight way to
flag bad answers so quality improves over time.
AC:
- Thumbs up/down control on assistant messages
- Feedback payload includes persona + module + message id
- Fire-and-forget (no blocking UI), fails silently with local log on
  network error

**1.4 "Re-answer with a different persona lens"** — p2, S
Story: As a BASIS admin reading an FI answer, I want to ask "explain this
for BASIS" without retyping the question.
AC:
- Long-press/menu action on any assistant message: "Explain for..." →
  persona picker
- Re-sends original question with new persona tag as a follow-up turn
- Original answer remains visible in history

---

## Epic 2 — Technical toolkit (ABAP code helper, dump decoder, tcode companion)

| # | Title | Labels | Effort |
|---|---|---|---|
| 2.1 | ST22 dump/error decoder | `abap`,`basis`,`feature`,`p0` | M |
| 2.2 | ABAP code helper (review/refactor/explain) | `abap`,`feature`,`p1` | M |
| 2.3 | Tcode + table quick-reference companion | `abap`,`basis`,`feature`,`p1` | M |
| 2.4 | Export decoded dump analysis as PDF/text | `abap`,`basis`,`feature`,`p2` | S |

**2.1 ST22 dump/error decoder** — p0, M
Story: As an ABAP developer staring at an ST22 short dump, I want to paste it
and get the root cause and a fix, instead of digging through the runtime
error screen manually.
AC:
- New composer mode (or paste-detection) recognizes ST22-shaped text
  (runtime error, exception class, where/call stack)
- Sends to chat with a dedicated prompt template requesting: root cause,
  offending code/config, suggested fix, relevant OSS notes if known
- Also accepts a pasted screenshot via existing file-attachment path
  (image → same flow)
- Response renders with clear sections (cause / fix / references)

**2.2 ABAP code helper** — p1, M
Story: As an ABAP developer, I want to paste a code snippet and get a
review, a refactor suggestion, or a plain-English explanation.
AC:
- Code input via composer (monospace-aware) or existing file attachment
- Three quick-action modes: Explain / Review / Refactor, each with a
  distinct prompt template
- Response preserves code blocks with syntax highlighting (existing
  `MarkdownView`/Code views)

**2.3 Tcode + table quick-reference companion** — p1, M
Story: As a BASIS or ABAP consultant, I want to quickly look up what a
tcode does and its related tables without leaving the app.
AC:
- Search field for tcode or table name
- Returns description, module, related tcodes/tables (via chat call with a
  lookup-style prompt, not a static offline DB)
- Recent lookups cached locally for offline re-view
- Result can be sent into main chat as follow-up context

**2.4 Export decoded dump analysis as PDF/text** — p2, S
Story: As a BASIS admin, I want to export a dump analysis to attach to a
ticket.
AC:
- Share sheet action on a dump-decoder result: export as PDF or plain text
- Includes original dump excerpt + AI analysis
- Uses existing share/export plumbing if present, else
  `UIActivityViewController`

---

## Epic 3 — Functional toolkit (FI, FI-CA, IS-U)

| # | Title | Labels | Effort |
|---|---|---|---|
| 3.1 | SPRO/config explainer | `fi`,`is-u`,`feature`,`p1` | M |
| 3.2 | Process Q&A mode with linked tcodes | `fi`,`is-u`,`feature`,`p1` | M |
| 3.3 | Requirement → functional spec drafter | `fi`,`is-u`,`feature`,`p1` | L |
| 3.4 | FI-CA/IS-U glossary quick-lookup | `fi`,`is-u`,`feature`,`p2` | S |

**3.1 SPRO/config explainer** — p1, M
Story: As an FI functional consultant, I want to paste an IMG/SPRO node
path and get a plain-English explanation of what it configures and its
business impact.
AC:
- Composer mode accepts an SPRO path or config node name
- Response explains: what it controls, dependencies, common
  misconfigurations
- Works for both FI and IS-U flavored config nodes

**3.2 Process Q&A mode with linked tcodes** — p1, M
Story: As an IS-U consultant, I want to ask how a business process works
end-to-end and get the tcode sequence, not just prose.
AC:
- Dedicated prompt template that requests a structured step list (step,
  tcode, purpose)
- Rendered as a numbered checklist in-app, tappable to send "explain step
  N" as follow-up
- Covers both FI and IS-U example processes in initial prompt tuning

**3.3 Requirement → functional spec drafter** — p1, L
Story: As a functional consultant, I want to paste a raw business
requirement and get a structured draft spec to start from.
AC:
- Text input for raw requirement (composer or dedicated screen)
- Output includes: as-is/to-be summary, config steps, testing notes, open
  questions
- Draft is copyable/exportable (reuse 2.4 export plumbing)
- Explicitly labeled as a draft requiring consultant review (no unqualified
  claims of completeness)

**3.4 FI-CA/IS-U glossary quick-lookup** — p2, S
Story: As a consultant new to IS-U, I want a fast lookup for domain jargon.
AC:
- Inline search panel, same UI pattern as 2.3 tcode lookup
- Backed by chat call with a glossary-style prompt
- Recent lookups cached locally

---

## Epic 4 — Leader toolkit (SI founders / leaders)

| # | Title | Labels | Effort |
|---|---|---|---|
| 4.1 | Proposal/estimate helper | `leader`,`feature`,`p1` | L |
| 4.2 | Client-ready "talking points" export | `leader`,`feature`,`p2` | S |
| 4.3 | SAP market signal digest | `leader`,`feature`,`p2` | L |
| 4.4 | Weekly personal usage digest | `leader`,`feature`,`p2` | M |

**4.1 Proposal/estimate helper** — p1, L
Story: As an SI founder, I want to describe a prospective SAP engagement
and get a structured draft estimate (phases, roles, rough hours) to start
a real proposal from.
AC:
- Dedicated input for engagement description (scope, modules, systems
  involved)
- Output: phase breakdown, role mix, rough hour ranges, key
  risks/assumptions
- Clearly labeled as a starting draft, not a quote
- Exportable (reuse 2.4/3.3 export plumbing)

**4.2 Client-ready "talking points" export** — p2, S
Story: As a leader, I want to turn any chat answer into a clean one-pager
I can hand to a client.
AC:
- Share action on any assistant message: "Export as talking points"
- Reformats into a leader-friendly layout (headline, bullets, no raw
  markdown artifacts)
- Includes BlueFunda footer (shared component with 5.1)

**4.3 SAP market signal digest** — p2, L
Story: As an SI founder, I want a periodic summary of SAP ecosystem trends
relevant to my business.
AC:
- Needs a content source decision first (flag: likely requires a backend
  content pipeline, not purely client-side — scope a spike before
  committing to L estimate)
- In-app surface (e.g. a digest tab/card) rendering the latest digest
- Digest is dated and dismissible

**4.4 Weekly personal usage digest** — p2, M
Story: As a leader, I want a weekly nudge showing what I've been using the
app for, to reinforce habit.
AC:
- Local, on-device summary (message count, top personas/topics used) — no
  new backend dependency required for v1
- Delivered as an in-app card or local notification
- No cross-user comparison in v1 (avoid implying analytics/tracking of
  peers without a privacy review)

---

## Epic 5 — Engagement mechanics

| # | Title | Labels | Effort |
|---|---|---|---|
| 5.1 | One-tap shareable answer card with BlueFunda footer | `feature`,`p0` | M |
| 5.2 | Persona-based onboarding flow | `feature`,`p1` | M |
| 5.3 | Daily push wrapper for Tip Engine content | `feature`,`p1` | S |
| 5.4 | Streak indicator for daily engagement | `feature`,`p2` | S |
| 5.5 | Share-to-network deep link with attribution | `feature`,`p2` | M |

**5.1 One-tap shareable answer card** — p0, M
Story: As any user, I want to share a good answer to LinkedIn/WhatsApp with
one tap in a branded format, so sharing becomes free marketing.
AC:
- Share action renders the Q&A as a styled image/text card with BlueFunda
  logo + footer
- Uses standard `UIActivityViewController` share sheet
- Card readable at typical social preview sizes (test on at least one
  target size)
- No sensitive system names/credentials ever included if the answer
  referenced a connected SAP system

**5.2 Persona-based onboarding flow** — p1, M
Story: As a first-time user, I want a quick setup that tailors the app to
my SAP role.
AC:
- First-launch flow: pick persona (ABAP/BASIS/FI/IS-U/Leader), feeds
  directly into 1.1's persona field
- Skippable, defaults to "General" if skipped
- Shown once (tracked via local flag), re-accessible from Settings

**5.3 Daily push wrapper for Tip Engine content** — p1, S
Story: As a returning user, I want a daily nudge with a useful SAP tip so
opening the app becomes a habit.
AC:
- Thin client feature: local/push notification surfacing whatever the Tip
  Engine (#155–160) returns — no new tip-selection logic built here, this
  issue is explicitly blocked on Tip Engine Phases 1–5 landing
- Tapping notification opens the app to the relevant tip/tcode-of-the-day
  context
- Respects existing notification permission flow

**5.4 Streak indicator** — p2, S
Story: As a user building a habit, I want to see a visible streak so I'm
motivated to keep opening the app.
AC:
- Local day-over-day open tracking, no backend dependency
- Small badge/indicator (e.g. "3-day streak") shown on a relevant screen
- Resets cleanly, no negative/shaming framing on reset

**5.5 Share-to-network deep link** — p2, M
Story: As a user sharing an answer, I want the link to open the recipient
straight into the app (or App Store) with attribution back to me.
AC:
- Deep link scheme opens the shared Q&A directly if the app is installed
- Falls back to App Store link if not installed
- Attribution parameter captured for basic referral counting (no PII in
  the link)

---

**Totals:** 5 epics + 22 child issues = 27 issues, 11 new labels, 3
milestones. P0 set = 1.1, 2.1, 5.1, plus their parent epics.
