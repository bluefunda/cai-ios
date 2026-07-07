# Changelog

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
