# CI/CD

Two workflows in `.github/workflows/`: `ci.yml` (every PR and push to `main`) and `release-please.yml` (release automation, `main` only).

---

## `ci.yml` — runs on every PR and push to `main`

| Job | What it does | Blocks merge on |
|---|---|---|
| `lint` | `swiftlint lint` against the whole `CAI/` tree, using the repo's `.swiftlint.yml` | Any rule at **error** severity. Style-only nits stay warnings and don't block. |
| `build-test` | Builds Debug and runs `CAITests` on an iOS Simulator | Any test failure or build error |
| `build-macos` | Unsigned build-only smoke test for Mac Catalyst (`generic/platform=macOS,variant=Mac Catalyst`) | Any compile/link error — this is what catches "works on iOS, doesn't compile for Mac" regressions before they reach `main` |

`build-macos` intentionally doesn't run unit tests or sign anything — it exists purely to catch Catalyst-specific build breaks (missing `#if os(iOS)` guard, iOS-only API used unconditionally, etc.) on every PR, without needing a Mac provisioning profile in the PR context.

### Why `.swiftlint.yml` disables some rules

The codebase predates SwiftLint being added to CI. `identifier_name`, `force_try`, `trailing_comma`, `cyclomatic_complexity`, and `function_body_length` are disabled because a first pass found real, non-trivial violations (a 44-complexity parsing function, several short-but-intentional identifiers) that are out of scope to refactor as part of adding CI — see the comment in `.swiftlint.yml` for exactly which files. `file_length` and `type_body_length` are raised just above today's high-water mark instead of disabled, so new files/types can't grow past current levels without CI catching it.

---

## `release-please.yml` — runs on push to `main`

```
push to main
  → release-please job (shared bluefunda/.github workflow)
      · scans conventional commits since the last tag
      · opens/updates a Release PR with the computed version + changelog
      · when that Release PR is merged: creates a GitHub Release + tag (vX.Y.Z)
        and sets release_created=true
  → (only if release_created) ios-deploy job
      · installs the distribution cert + iOS provisioning profile
      · bundle exec fastlane ios ios_upload  (build, sign, upload — no submit)
  → (only if release_created) macos-deploy job
      · installs the distribution cert + macOS provisioning profile
      · bundle exec fastlane ios mac_upload  (build, sign, upload — no submit)
  → (only if release_created) release-notes job
      · generates/posts release notes for the tag
```

`ios-deploy` and `macos-deploy` run in parallel — neither depends on the other. Both derive the same version/build number from `needs.release-please.outputs.tag_name` and `github.run_number`, so an iOS and macOS build produced by the same workflow run always carry matching version numbers.

**Neither job submits for review.** That's a deliberate, standing decision (see `fastlane/Fastfile` header comment) — a human runs `bundle exec fastlane ios_submit` / `mac_submit` locally, or via a separately-triggered `workflow_dispatch` job, after checking the processed build in App Store Connect.

### Required secrets

See [CODE_SIGNING.md](CODE_SIGNING.md#option-a-github-actions-secrets-cicd) for the full table and how to generate each value. Summary: one distribution cert + ASC API key shared by both platforms, one provisioning profile per platform.

---

## Adding a new CI job

- PR-blocking checks go in `ci.yml`.
- Anything that touches Apple credentials or uploads a build goes in `release-please.yml`, gated behind `needs.release-please.outputs.release_created == 'true'` — never run signing steps on every push, only on an actual release.
