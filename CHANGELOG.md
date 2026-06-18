# Changelog

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
