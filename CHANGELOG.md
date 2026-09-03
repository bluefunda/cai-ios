# Changelog

## [2.5.0](https://github.com/bluefunda/cai-ios/compare/v2.4.4...v2.5.0) (2026-09-03)


### Features

* add camera capture to composer, fix attachment and streaming edge cases ([8a30acd](https://github.com/bluefunda/cai-ios/commit/8a30acd2e993725e85ca4303a998cc8299fd1d1d))

## [2.4.4](https://github.com/bluefunda/cai-ios/compare/v2.4.3...v2.4.4) (2026-09-01)


### Bug Fixes

* **chat:** fix streaming render performance, trailing fade, and empty-state scroll ([a341216](https://github.com/bluefunda/cai-ios/commit/a3412166b7ee11c67ad87f1607da6bdf3e467f91))
* **chat:** streaming render performance, trailing fade, and empty-state scroll ([553580f](https://github.com/bluefunda/cai-ios/commit/553580f17807b1506f75bd9a094847178cb9392e))

## [2.4.3](https://github.com/bluefunda/cai-ios/compare/v2.4.2...v2.4.3) (2026-08-31)


### Bug Fixes

* **chat:** stopped messages can un-freeze and replay after a later prompt ([c359326](https://github.com/bluefunda/cai-ios/commit/c359326730be508c83ad6a593813cda13be7f415))
* **chat:** stopped messages can un-freeze and replay after a later prompt ([dc62ce7](https://github.com/bluefunda/cai-ios/commit/dc62ce7eecd8a8d0ccbc0dd912ac36e1aeda08bf))

## [2.4.2](https://github.com/bluefunda/cai-ios/compare/v2.4.1...v2.4.2) (2026-08-31)


### Bug Fixes

* **chat:** stop-button reliability, streaming content corruption, and reveal performance ([9be39f4](https://github.com/bluefunda/cai-ios/commit/9be39f42f68e6a523d0cba30aaeb265d9348193f))
* **chat:** stop-button reliability, streaming content corruption, and reveal performance ([6a71a74](https://github.com/bluefunda/cai-ios/commit/6a71a743bca17dedce970518fe87747f81ba85f4))

## [2.4.1](https://github.com/bluefunda/cai-ios/compare/v2.4.0...v2.4.1) (2026-08-28)


### Bug Fixes

* **settings:** don't default straight into Account on open ([46464ae](https://github.com/bluefunda/cai-ios/commit/46464ae4defed576f50a4ddfa3300b3d8cff4950))

## [2.4.0](https://github.com/bluefunda/cai-ios/compare/v2.3.1...v2.4.0) (2026-08-28)


### Features

* **chat:** add paced markdown rendering for smoother streaming output ([5e5a5ca](https://github.com/bluefunda/cai-ios/commit/5e5a5ca284b7ec554e7c5bbfb873eecd539fa911))
* **chat:** frame-synced reveal ticker + Android streaming/scroll parity ([9913a66](https://github.com/bluefunda/cai-ios/commit/9913a66cb3e3f6e6abd5434fe788ca476a410b62))
* Mac/iPad top bar cleanup, Settings restructure, sidebar toggle, iOS keyboard spacing ([294906c](https://github.com/bluefunda/cai-ios/commit/294906cca3e58db59402297f0f81f3b0bc6d209d))


### Bug Fixes

* **chat:** background reconciliation, cold-launch, and Android streaming/scroll parity ([#261](https://github.com/bluefunda/cai-ios/issues/261)) ([326b861](https://github.com/bluefunda/cai-ios/commit/326b861ac7f30c28908b842ba3802ff4a35759f1))
* **chat:** reconcile interrupted stream after app backgrounds ([#261](https://github.com/bluefunda/cai-ios/issues/261)) ([d691014](https://github.com/bluefunda/cai-ios/commit/d6910147856f4f9691a7adac9a5ea00d963e3578))
* **chat:** render LaTeX/tables/nested lists, add syntax highlighting and reveal-ticker pacing ([#250](https://github.com/bluefunda/cai-ios/issues/250)) ([9f0ae28](https://github.com/bluefunda/cai-ios/commit/9f0ae28619d9aa06c8d2f2b61bd72233a4642e25))
* **chat:** reopen into the last active conversation instead of the greeting screen ([8f04c86](https://github.com/bluefunda/cai-ios/commit/8f04c861249c5ec03b25b9b4956e1c54e0d70110))
* don't restore the last conversation on a fresh app launch ([2f8a199](https://github.com/bluefunda/cai-ios/commit/2f8a199739554488e4a777641f1381932dd5c1ea))
* reconcile chat stream after app backgrounds ([#261](https://github.com/bluefunda/cai-ios/issues/261)) ([e1375d2](https://github.com/bluefunda/cai-ios/commit/e1375d2f20b7febc0fcdda06bfd8168f17edbde1))
* retry stream reconciliation instead of giving up after one attempt ([34b0406](https://github.com/bluefunda/cai-ios/commit/34b040614007d7a7c319de2266e125dc1d0d109a))
* split ChatManager to clear SwiftLint's file_length CI check ([3660814](https://github.com/bluefunda/cai-ios/commit/36608145ded84db5cf62be57212441d500af52d8))

## [2.3.1](https://github.com/bluefunda/cai-ios/compare/v2.3.0...v2.3.1) (2026-08-20)


### Bug Fixes

* **chat:** render LaTeX math notation as Unicode symbols ([#243](https://github.com/bluefunda/cai-ios/issues/243)) ([b88a731](https://github.com/bluefunda/cai-ios/commit/b88a73160eb4e06636e6271f841aacadeb82c14b)), closes [#242](https://github.com/bluefunda/cai-ios/issues/242)
* **subscription:** keep hasActiveSubscription in sync with backend ([#241](https://github.com/bluefunda/cai-ios/issues/241)) ([c2f0b25](https://github.com/bluefunda/cai-ios/commit/c2f0b25a64f5109e2d8019e3af33da87a1b41178))

## [2.3.0](https://github.com/bluefunda/cai-ios/compare/v2.2.2...v2.3.0) (2026-08-19)


### Features

* **persona:** replace hardcoded persona enum with cai-mcp-go's /personas API ([4769be4](https://github.com/bluefunda/cai-ios/commit/4769be46ea7467a65b2c302653befbc28e80fe87))
* **persona:** replace hardcoded persona enum with cai-mcp-go's /personas API ([7115e78](https://github.com/bluefunda/cai-ios/commit/7115e7868580011388a05e8146c1ad877474804e)), closes [#244](https://github.com/bluefunda/cai-ios/issues/244)


### Bug Fixes

* **persona:** filter General out of the fetched backend catalog ([a31ce7c](https://github.com/bluefunda/cai-ios/commit/a31ce7cf91a09dc488833e6639eddc361f9d7dcf))
* **persona:** force a real persona when the composer toggle turns on ([1f8b94c](https://github.com/bluefunda/cai-ios/commit/1f8b94cf6401202199deabb3bb88eca7f863b2d3))
* **persona:** sanitize pre-existing disk cache on read, not just fetch ([813d3fb](https://github.com/bluefunda/cai-ios/commit/813d3fb78299bebe0321993b851820c86ac0933d))

## [2.2.2](https://github.com/bluefunda/cai-ios/compare/v2.2.1...v2.2.2) (2026-08-13)


### Bug Fixes

* **subscription:** correct Pro plan description to match web app ([#238](https://github.com/bluefunda/cai-ios/issues/238)) ([b5d3e8c](https://github.com/bluefunda/cai-ios/commit/b5d3e8ce57879d4760b54fff8acff81b509473c0))

## [2.2.1](https://github.com/bluefunda/cai-ios/compare/v2.2.0...v2.2.1) (2026-08-12)


### Bug Fixes

* **subscription:** show correct Pro label for Stripe subscribers on iOS ([#235](https://github.com/bluefunda/cai-ios/issues/235)) ([250825c](https://github.com/bluefunda/cai-ios/commit/250825c2d5bca25599cfe3c43761e0e56f708d39))

## [2.2.0](https://github.com/bluefunda/cai-ios/compare/v2.1.1...v2.2.0) (2026-08-11)


### Features

* **chat:** brand-refreshed app icon and streaming indicator ([#227](https://github.com/bluefunda/cai-ios/issues/227)) ([1ccc324](https://github.com/bluefunda/cai-ios/commit/1ccc3243df8dfb387daa01883ab1fbdb04228587))

## [2.1.1](https://github.com/bluefunda/cai-ios/compare/v2.1.0...v2.1.1) (2026-08-10)


### Bug Fixes

* **chat:** move composer accessory row below the text field ([#224](https://github.com/bluefunda/cai-ios/issues/224)) ([b600be2](https://github.com/bluefunda/cai-ios/commit/b600be2f236d27abd4bf2dd2c31c291764fa6443))

## [2.1.0](https://github.com/bluefunda/cai-ios/compare/v2.0.0...v2.1.0) (2026-08-07)


### Features

* move SAP persona controls into chat composer, per-conversation scope ([#221](https://github.com/bluefunda/cai-ios/issues/221)) ([57517b4](https://github.com/bluefunda/cai-ios/commit/57517b47116ce7a8790a038fe8a24bc008baa3e4))

## [2.0.0](https://github.com/bluefunda/cai-ios/compare/v1.9.0...v2.0.0) (2026-08-03)


### ⚠ BREAKING CHANGES

* enable SAP persona wire by default, fix .general omission bug ([#217](https://github.com/bluefunda/cai-ios/issues/217))

### Features

* enable SAP persona wire by default, fix .general omission bug ([#217](https://github.com/bluefunda/cai-ios/issues/217)) ([608fd71](https://github.com/bluefunda/cai-ios/commit/608fd71c83786dec1550ce1a3e1744c8d25cc63a))


### Bug Fixes

* **markdown:** render tables as stacked cards instead of horizontal scroll ([#215](https://github.com/bluefunda/cai-ios/issues/215)) ([5c8969f](https://github.com/bluefunda/cai-ios/commit/5c8969f204666f5516d1a5da3f023c6fa79b26ca))

## [1.9.0](https://github.com/bluefunda/cai-ios/compare/v1.8.2...v1.9.0) (2026-08-02)


### Features

* multi-MCP wire format, SAP persona (selector + depth epic), ST22 decoder, shareable answer card ([#212](https://github.com/bluefunda/cai-ios/issues/212)) ([0c7dfae](https://github.com/bluefunda/cai-ios/commit/0c7dfaeb813385a9e6c850f46fd9a6c762ba9f62))

## [1.8.2](https://github.com/bluefunda/cai-ios/compare/v1.8.1...v1.8.2) (2026-07-30)


### Bug Fixes

* **markdown:** table rendering + perf; feat(mcp): multi-select assistants ([#166](https://github.com/bluefunda/cai-ios/issues/166)) ([378cea9](https://github.com/bluefunda/cai-ios/commit/378cea9a147329b533dfe010faec61866c6ae3ca))

## [1.8.1](https://github.com/bluefunda/cai-ios/compare/v1.8.0...v1.8.1) (2026-07-28)


### Bug Fixes

* **ci:** fall back to a PR when the release-sync push to main is rejected ([#153](https://github.com/bluefunda/cai-ios/issues/153)) ([318d64d](https://github.com/bluefunda/cai-ios/commit/318d64d573087a50355a80a57b2f8ccd356182df))

## [1.8.0](https://github.com/bluefunda/cai-ios/compare/v1.7.1...v1.8.0) (2026-07-25)


### Features

* local file persistence, prompt attachments, and voice input ([#150](https://github.com/bluefunda/cai-ios/issues/150)) ([fb7777f](https://github.com/bluefunda/cai-ios/commit/fb7777f1d8a63837879a666d7bddfe766b5bcfe5))

## [1.7.1](https://github.com/bluefunda/cai-ios/compare/v1.7.0...v1.7.1) (2026-07-22)


### Bug Fixes

* **auth:** resolve immediate session expiry after login on iOS ([#146](https://github.com/bluefunda/cai-ios/issues/146)) ([4dae0b1](https://github.com/bluefunda/cai-ios/commit/4dae0b18ef5bc01226df9249fca10d13e417efa5))

## [1.7.0](https://github.com/bluefunda/cai-ios/compare/v1.6.4...v1.7.0) (2026-07-16)


### Features

* **rate-limit:** use server-provided reset_label, remove local time formatting ([#144](https://github.com/bluefunda/cai-ios/issues/144)) ([b30d64c](https://github.com/bluefunda/cai-ios/commit/b30d64c7cecbc1d11b7e3d258647fe4adab8fd75))

## [1.6.4](https://github.com/bluefunda/cai-ios/compare/v1.6.3...v1.6.4) (2026-07-15)


### Bug Fixes

* **rate-limit:** show days in reset label and add manual deploy trigger ([#142](https://github.com/bluefunda/cai-ios/issues/142)) ([19407a2](https://github.com/bluefunda/cai-ios/commit/19407a2a974cf10a01a2bdf17c2c30d830315237))

## [1.6.3](https://github.com/bluefunda/cai-ios/compare/v1.6.2...v1.6.3) (2026-07-14)


### Bug Fixes

* rate limit UX — banners, usage bars, and unlimited plan support ([#139](https://github.com/bluefunda/cai-ios/issues/139)) ([aeacf4b](https://github.com/bluefunda/cai-ios/commit/aeacf4bd6833181a82c156c743d9c9e47ec8bfe2))

## [1.6.2](https://github.com/bluefunda/cai-ios/compare/v1.6.1...v1.6.2) (2026-07-13)


### Bug Fixes

* screenshot uploads + macOS-specific metadata + iOS deploy pause switch ([#135](https://github.com/bluefunda/cai-ios/issues/135)) ([6f79f59](https://github.com/bluefunda/cai-ios/commit/6f79f59acb7fb120b4e1eb8175eaf5ca49056463))

## [1.6.1](https://github.com/bluefunda/cai-ios/compare/v1.6.0...v1.6.1) (2026-07-12)


### Bug Fixes

* pin ruby-version in release-please.yml deploy jobs ([#132](https://github.com/bluefunda/cai-ios/issues/132)) ([cd7c9e3](https://github.com/bluefunda/cai-ios/commit/cd7c9e35c78c1c0c9b3bc3844c7647f590e54af1)), closes [#131](https://github.com/bluefunda/cai-ios/issues/131)

## [1.6.0](https://github.com/bluefunda/cai-ios/compare/v1.5.0...v1.6.0) (2026-07-12)


### Features

* enable production macOS (Mac Catalyst) release pipeline ([#126](https://github.com/bluefunda/cai-ios/issues/126)) ([e64d92d](https://github.com/bluefunda/cai-ios/commit/e64d92db6f5aa36741be1f739d8db0a8b2c317c7))


### Bug Fixes

* repair macOS upload pipeline bugs found in first real run ([#130](https://github.com/bluefunda/cai-ios/issues/130)) ([c67d744](https://github.com/bluefunda/cai-ios/commit/c67d744b4f5076b8dedfdc519b92be26f802e43c))

## [1.5.0](https://github.com/bluefunda/cai-ios/compare/v1.4.0...v1.5.0) (2026-07-08)


### Features

* add In-App Purchase subscription for individual users ([#123](https://github.com/bluefunda/cai-ios/issues/123)) ([4a75021](https://github.com/bluefunda/cai-ios/commit/4a75021b02bf946503055cde8c7b92373288254e))

## [1.4.0](https://github.com/bluefunda/cai-ios/compare/v1.3.0...v1.4.0) (2026-07-07)


### Features

* add In-App Purchase subscription for individual users ([#120](https://github.com/bluefunda/cai-ios/issues/120)) ([#121](https://github.com/bluefunda/cai-ios/issues/121)) ([c67caa4](https://github.com/bluefunda/cai-ios/commit/c67caa46986bf2cc256efe7dd034a2144c816aba))

## [1.3.0](https://github.com/bluefunda/cai-ios/compare/v1.2.3...v1.3.0) (2026-07-05)


### Features

* add copy/share actions to user prompts and assistant responses ([#118](https://github.com/bluefunda/cai-ios/issues/118)) ([79eed8b](https://github.com/bluefunda/cai-ios/commit/79eed8b2a7dd52a0c50449558084c9f5af8d8e8d))


### Bug Fixes

* refresh access token per request and handle expired sessions gracefully ([#115](https://github.com/bluefunda/cai-ios/issues/115)) ([cbd3b57](https://github.com/bluefunda/cai-ios/commit/cbd3b57a56aae345c75346c81cf6f4b49553b37b))

## [1.2.3](https://github.com/bluefunda/cai-ios/compare/v1.2.2...v1.2.3) (2026-07-02)


### Bug Fixes

* remove subscription tier indicators to comply with App Store guideline 3.1.1 ([#111](https://github.com/bluefunda/cai-ios/issues/111)) ([fbbc112](https://github.com/bluefunda/cai-ios/commit/fbbc1129099c76092b8090c42dcd3fa460dced72))

## [1.2.2](https://github.com/bluefunda/cai-ios/compare/v1.2.1...v1.2.2) (2026-07-02)


### Bug Fixes

* rename 'Subscription' section headers to comply with App Store 3.1.1 ([#109](https://github.com/bluefunda/cai-ios/issues/109)) ([a6fd151](https://github.com/bluefunda/cai-ios/commit/a6fd1513e4660ff0fe974303b927b35f0459c97d)), closes [#108](https://github.com/bluefunda/cai-ios/issues/108)

## [1.2.1](https://github.com/bluefunda/cai-ios/compare/v1.2.0...v1.2.1) (2026-07-01)


### Bug Fixes

* refactor IDP button styling and Apple Sign In coordinator ([976b473](https://github.com/bluefunda/cai-ios/commit/976b47368e7b257a18cf5333521dd9ee06c62c71))
* updating login screen styling changes ([952d2a8](https://github.com/bluefunda/cai-ios/commit/952d2a8a8660145c1227d94de0ea290b66736056))

## [1.2.0](https://github.com/bluefunda/cai-ios/compare/v1.1.1...v1.2.0) (2026-07-01)


### Features

* **auth:** harden Apple Sign In with PKCE, nonce, state, and reviewer fallback ([#88](https://github.com/bluefunda/cai-ios/issues/88)) ([d3fa7e8](https://github.com/bluefunda/cai-ios/commit/d3fa7e8065d50ddad0fb40b09258fdf85054bdd2))
* **brand:** add BFLogo component, button styles, and logo asset catalog ([#83](https://github.com/bluefunda/cai-ios/issues/83)) ([07af071](https://github.com/bluefunda/cai-ios/commit/07af071104194df6e3b445ae9beca230363ed457))
* **brand:** add design token system and migrate views to brand colors ([#80](https://github.com/bluefunda/cai-ios/issues/80)) ([873bf28](https://github.com/bluefunda/cai-ios/commit/873bf28296c75c2c7833dfedf8f083900170fcb9))
* **chat:** send file attachment as fileUrl in request payload instead of embedding URL in prompt text ([#98](https://github.com/bluefunda/cai-ios/issues/98)) ([046c5dc](https://github.com/bluefunda/cai-ios/commit/046c5dc126eeb559cde268c9fad6b1d655e03277))
* iPad layout, Mac Catalyst, native Apple Sign In, ABAP system management ([#104](https://github.com/bluefunda/cai-ios/issues/104)) ([046c5dc](https://github.com/bluefunda/cai-ios/commit/046c5dc126eeb559cde268c9fad6b1d655e03277))


### Bug Fixes

* App Store review resubmission — auth, version, and UI fixes ([#95](https://github.com/bluefunda/cai-ios/issues/95)) ([8a2a2d7](https://github.com/bluefunda/cai-ios/commit/8a2a2d7167277c34704000ca059badf9de1c43e2))
* **chat:** fire title generation in parallel, not gated on stream_end ([#84](https://github.com/bluefunda/cai-ios/issues/84)) ([94973a1](https://github.com/bluefunda/cai-ios/commit/94973a1b899740040d337e49540a588ee8fbbc28))
* **chat:** fix invisible user messages in dark mode ([#85](https://github.com/bluefunda/cai-ios/issues/85)) ([ba33731](https://github.com/bluefunda/cai-ios/commit/ba33731e72048c998184249d66acda44937905fc))
* **chat:** use adaptive .primary for user message text in dark mode ([#86](https://github.com/bluefunda/cai-ios/issues/86)) ([da669c5](https://github.com/bluefunda/cai-ios/commit/da669c505670275eefad602eb84c28980eaf034a))

## [1.1.1](https://github.com/bluefunda/cai-ios/compare/v1.1.0...v1.1.1) (2026-06-24)


### Bug Fixes

* updated text color in the apple signin button ([#67](https://github.com/bluefunda/cai-ios/issues/67)) ([fb72a4a](https://github.com/bluefunda/cai-ios/commit/fb72a4a6af890845aa1245c9bef3c2f5ba6ded7b))

## [1.1.0](https://github.com/bluefunda/cai-ios/compare/v1.0.4...v1.1.0) (2026-06-24)


### Features

* **login:** redesign login screen with BlueFunda AI branding and social sign-in ([e01b9ec](https://github.com/bluefunda/cai-ios/commit/e01b9ecadfc6bb03f4ec8e7603efd0b0d0e6f1e6))


### Bug Fixes

* **login:** Updated login screen design changes and skipped login with keycloak button routing ([75ebae6](https://github.com/bluefunda/cai-ios/commit/75ebae6ae0dcd1e7a269cd2feea0d7cc1d89da46))

## [1.0.4](https://github.com/bluefunda/cai-ios/compare/v1.0.3...v1.0.4) (2026-06-18)


### Bug Fixes

* **chat:** clear user state on disconnect to prevent stale data after account deletion ([#63](https://github.com/bluefunda/cai-ios/issues/63)) ([d5af340](https://github.com/bluefunda/cai-ios/commit/d5af340784f32dc2dd9212c311b1fac8dfd22c5e))

## [1.0.3](https://github.com/bluefunda/cai-ios/compare/v1.0.2...v1.0.3) (2026-06-17)


### Bug Fixes

* **chat:** clear user state on disconnect to prevent stale data after account deletion ([#61](https://github.com/bluefunda/cai-ios/issues/61)) ([0134871](https://github.com/bluefunda/cai-ios/commit/013487114e8a197edb8c82f24b4bb3aea2822763))

## [1.0.2](https://github.com/bluefunda/cai-ios/compare/v1.0.1...v1.0.2) (2026-06-17)


### Bug Fixes

* **account:** use Authorization Bearer header for delete account request ([#59](https://github.com/bluefunda/cai-ios/issues/59)) ([8ab80fc](https://github.com/bluefunda/cai-ios/commit/8ab80fc340667dda402a2c8fcbab9db7c1701ef6))

## [1.0.1](https://github.com/bluefunda/cai-ios/compare/v1.0.0...v1.0.1) (2026-06-15)


### Bug Fixes

* **ci:** specify manual signing in ExportOptions.plist for exportArchive ([#56](https://github.com/bluefunda/cai-ios/issues/56)) ([f31f2f3](https://github.com/bluefunda/cai-ios/commit/f31f2f3fbe21eaf015ddb44f836ced4fdc83e608))

## 1.0.0 (2026-06-15)


### Features

* **account:** delete account (DELETE /ai/user) ([#53](https://github.com/bluefunda/cai-ios/issues/53)) ([4ed7f4f](https://github.com/bluefunda/cai-ios/commit/4ed7f4f57efbcdb046baacfdbbd9820f628dfd54))
* add BlueFunda brand icon and fix CFBundleIconName ([cf87695](https://github.com/bluefunda/cai-ios/commit/cf87695d0b0d105e35994d673b43976bbee7d753))
* **chat:** combined thinking-mode + LLM dropdown ([#23](https://github.com/bluefunda/cai-ios/issues/23)) ([#30](https://github.com/bluefunda/cai-ios/issues/30)) ([5072eb2](https://github.com/bluefunda/cai-ios/commit/5072eb2d13223fbd65996255224f3f53a11e837a))
* **chat:** haptics, suggested prompts, share transcript ([#13](https://github.com/bluefunda/cai-ios/issues/13) [#11](https://github.com/bluefunda/cai-ios/issues/11) [#10](https://github.com/bluefunda/cai-ios/issues/10)) ([#51](https://github.com/bluefunda/cai-ios/issues/51)) ([285c470](https://github.com/bluefunda/cai-ios/commit/285c470b0cb87bdbb9a0d4e5e588d128437e622d))
* **chat:** markdown rendering for AI message bubbles ([#2](https://github.com/bluefunda/cai-ios/issues/2)) ([#16](https://github.com/bluefunda/cai-ios/issues/16)) ([430d4c5](https://github.com/bluefunda/cai-ios/commit/430d4c5f8084a748c25b98fbc0fb3981d88d015d))
* **code:** Phase 0 — Chat / &lt;/&gt;Code top-level tab navigation ([#48](https://github.com/bluefunda/cai-ios/issues/48)) ([4c719d1](https://github.com/bluefunda/cai-ios/commit/4c719d15bc15a685fef66bff309ef2ae916cc447))
* **compliance:** add content reporting, legal links, AI disclaimer; remove web checkout ([d55975a](https://github.com/bluefunda/cai-ios/commit/d55975a5dd441dd90e671d989f15032c38218076))
* **compliance:** content reporting, legal links, AI disclaimer; remove web checkout ([0e08f74](https://github.com/bluefunda/cai-ios/commit/0e08f74008624eafc1cafbbda69671a70cf34676))
* move Code into the sidebar + unified file/photo upload ([#49](https://github.com/bluefunda/cai-ios/issues/49) [#50](https://github.com/bluefunda/cai-ios/issues/50)) ([#52](https://github.com/bluefunda/cai-ios/issues/52)) ([2333f43](https://github.com/bluefunda/cai-ios/commit/2333f43e25c68f4718b0916f23194cbe2bbea4de))
* **settings:** realm-gate Connection and Build sections ([#27](https://github.com/bluefunda/cai-ios/issues/27)) ([667496e](https://github.com/bluefunda/cai-ios/commit/667496ebe82ec70bbf8cd7b2fa0ddb38cfa7ae3b))
* **storage,chat:** cloud storage browser, image attachments, CI fix ([#17](https://github.com/bluefunda/cai-ios/issues/17)) ([d455263](https://github.com/bluefunda/cai-ios/commit/d4552633b3c0d9c35eb3a1e609b629f021d99ba4))
* **ui:** sidebar nav, keyboard dismiss, scroll button, history fix ([#18](https://github.com/bluefunda/cai-ios/issues/18)) ([7dee680](https://github.com/bluefunda/cai-ios/commit/7dee680512cb7cce94513f3c05905a6dfb6ce8fb))
* **ui:** sidebar user avatar, Help/Upgrade links, copy/share on replies ([#28](https://github.com/bluefunda/cai-ios/issues/28)) ([7adfac8](https://github.com/bluefunda/cai-ios/commit/7adfac8da4968a4a086e91e66cc2bf140202146b)), closes [#24](https://github.com/bluefunda/cai-ios/issues/24) [#25](https://github.com/bluefunda/cai-ios/issues/25) [#26](https://github.com/bluefunda/cai-ios/issues/26)


### Bug Fixes

* **chat:** ChatGPT-style streaming scroll (pin prompt, show down arrow) ([#34](https://github.com/bluefunda/cai-ios/issues/34)) ([5d86ec4](https://github.com/bluefunda/cai-ios/commit/5d86ec4497916a67e3f3ec549fd28d3c16c2ed0a))
* **chat:** don't add empty "New Chat" drafts to history until first send ([#37](https://github.com/bluefunda/cai-ios/issues/37)) ([709d51c](https://github.com/bluefunda/cai-ios/commit/709d51ce5158b2b9868b31554ca5e86d25e02141))
* **chat:** reliable keyboard dismissal and cross-version scroll arrow ([#29](https://github.com/bluefunda/cai-ios/issues/29)) ([0a74415](https://github.com/bluefunda/cai-ios/commit/0a74415894eca51e063cdb4332699d771804f2e7))
* **chat:** send "prompt" (not "message") to title API so titles generate ([#35](https://github.com/bluefunda/cai-ios/issues/35)) ([dfae810](https://github.com/bluefunda/cai-ios/commit/dfae81058891c9aaf84e65c0e3d4319a2f86d88c))
* **chat:** send modelExplicit so LLM selection takes effect (match cai web) ([#31](https://github.com/bluefunda/cai-ios/issues/31)) ([32ffbfb](https://github.com/bluefunda/cai-ios/commit/32ffbfb377cbd11c3618578b14562859486f44bb))
* **history:** decode chatHistory key from BFF messages response ([#20](https://github.com/bluefunda/cai-ios/issues/20)) ([1ed05f3](https://github.com/bluefunda/cai-ios/commit/1ed05f366a9abe214e218d24e93b7e5228e60853))
* remove alpha channel from app icon (App Store error 90717) ([cd1e418](https://github.com/bluefunda/cai-ios/commit/cd1e418d03959ab1fc927d2e60f8c40a4de71774))
* **ui:** replace tuple KeyPath with Identifiable struct in ForEach ([#19](https://github.com/bluefunda/cai-ios/issues/19)) ([65f9a4a](https://github.com/bluefunda/cai-ios/commit/65f9a4a7402d476b81f69aa162949e2f2c31846c))
* use manual signing for Release to unblock App Store archive ([f047af3](https://github.com/bluefunda/cai-ios/commit/f047af36817a8ce27827154ef2a29ba1ca5f720e))
