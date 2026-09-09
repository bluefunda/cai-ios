import SwiftUI

// MARK: - Scroll Management
// Split from ChatView's main body to stay under SwiftLint's type_body_length/file_length limits
// (bluefunda/cai-ios#261 precedent — see ChatManager+Background.swift). file_length is measured
// per file, unlike type_body_length, so an extension needs its own file to help either.

extension ChatView {

    /// The most recently sent user message, if any — scrolling this to the
    /// top of the viewport on send (rather than jumping straight to the
    /// bottom) is what leaves room below it for the streaming response to
    /// fill in, matching cai-android's `MessageList` behavior.
    var latestUserMessageID: String? {
        chatManager.currentConversation?.messages.last(where: { $0.role == .user })?.id
    }

    /// Tracked separately from `latestUserMessageID` so the very first send can align the
    /// scroll view's layout (see the `.onChange(of: hasMessages)` handler) before the animated
    /// per-message scroll runs — matches cai-android's `LaunchedEffect(messages.isNotEmpty())`.
    var hasMessages: Bool {
        !(chatManager.currentConversation?.messages.isEmpty ?? true)
    }

    /// Bucketed (not raw) streaming content length, so `.onChange(of:)` below fires roughly every
    /// 20 characters instead of on every single token — following the growing response closely
    /// enough to read as smooth, without re-scrolling so often it costs real render time or reads
    /// as jittery. Needed because a growing row that's currently scrolled *out of* the viewport
    /// doesn't just silently extend the scrollable content below like it does in cai-android's
    /// LazyColumn — SwiftUI's List can let it visibly disturb whatever's currently on screen,
    /// which is what read as content "sticking to the top" with a hidden, growing gap above it
    /// and empty space below once the user scrolled away from the bottom.
    var streamingContentBucket: Int {
        guard chatManager.isStreaming,
              let id = chatManager.streamingMessageId,
              let content = chatManager.currentConversation?.messages.first(where: { $0.id == id })?.content
        else { return 0 }
        return content.count / 20
    }

    /// List's underlying UITableView/UICollectionView can scroll directly to a row regardless of
    /// whether it's been measured yet (unlike the LazyVStack this replaced) — matches cai-
    /// android's `LazyColumn.scrollToItem`, which has the same native guarantee. But mirroring
    /// cai-android exactly means mirroring its *whole* fix, not just the index-based scroll: it
    /// pairs that with `repeat(SCROLL_SETTLE_PASSES) { scrollToItem(...); withFrameNanos {} }`,
    /// because even a fully native scroll-to-row still races "the new data actually applied to
    /// the list" against "the scroll command was issued" — a single early call can silently
    /// no-op if List's diffable data source hasn't registered the new rows yet, and (unlike the
    /// LazyVStack version) there's nothing left to self-correct it afterward. Confirmed via a
    /// live on-device repro: a single call left a real conversation stuck at its first exchange
    /// instead of its end, immediately and durably (not just a slow-to-settle transient) — so
    /// this needs the same repeated-pass resilience Android relies on, not none at all. No
    /// animation, matching cai-android's equivalent settle scroll: this establishes where a
    /// freshly-switched-to conversation starts, not a visible transition to watch happen.
    func scrollToBottom(proxy: ScrollViewProxy) async {
        // cai-android's actual pass interval is withFrameNanos {} — one real display frame
        // (~16ms), not an arbitrary timer — so its whole settle loop finishes in a handful of
        // milliseconds and is never perceptible. This used Task.sleep(for: .milliseconds(100))
        // per pass — 6x slower than a frame — which made a plainly visible, sluggish "taking so
        // much time" delay on every single conversation switch, not just long ones. 16ms is the
        // closest plain-SwiftUI approximation (no CADisplayLink/frame-callback API here) to that
        // same per-frame cadence; more passes (10 vs. 6) keeps the same resilience margin for a
        // slow-to-lay-out long response while the *total* budget (~160ms) is still far under
        // what reads as sluggish.
        for _ in 0..<10 {
            guard !Task.isCancelled else { return }
            proxy.scrollTo("bottom", anchor: .bottom)
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    /// Scrolls a newly-sent user message to the top of the viewport, leaving room below for the
    /// streaming response — matches cai-android's `LaunchedEffect(latestUserMessageId)`. Shared by
    /// two call sites: the immediate `latestUserMessageID` change on send, and a second corrective
    /// re-run once `isStreaming` actually flips true (see that `.onChange` for why a truly cold
    /// app launch's slow first List layout can need this run twice — the first pass can settle on
    /// the row's height before it's fully reflowed).
    func scheduleNewPromptPositioning(id: String, proxy: ScrollViewProxy) {
        // Cancel any in-flight scrollSettleTask (from .onChange(of: hasMessages), which fires for
        // this same transition on the very first message) — that loop keeps re-anchoring to the
        // "bottom" sentinel for ~160ms after send, and once isStreaming's spacer appears mid-loop
        // it starts landing past the spacer instead of on this row, overriding this positioning
        // with a stale write moments after it lands.
        //
        // That cancellation can also land on an in-flight conversation-switch task (.onAppear /
        // currentConversation.id) before it reaches its own `isSwitchingConversation = false` —
        // cooperative cancellation means that reset never runs, leaving the loading overlay stuck
        // on forever. Real content (the message just sent/streaming) is about to render regardless,
        // so it's always correct to drop the switching overlay here too.
        chatManager.isSwitchingConversation = false
        // Stale from whatever the previous turn's response ended on — nil defaults the
        // streaming follow-scroll gate to "always catch up" until this new turn's own row
        // reports a real position, which is exactly the behavior wanted for a fresh send.
        streamingRowBottomY = nil
        scrollSettleTask?.cancel()
        scrollSettleTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(50))
            // A newly-appended row (the message just sent) can hit the same unmeasured-content
            // race scrollToBottom exists to cover elsewhere — a single scrollTo(anchor: .top)
            // attempted before List has laid it out can land with its top edge cut off under the
            // header instead of properly positioned, self-correcting only once real content starts
            // streaming and forces another layout pass. A few quick, unanimated warm-up passes
            // first aren't meant to be seen — they just get this row's geometry established so the
            // actual visible motion (the animated pass after) lands accurately on the first try.
            for _ in 0..<3 {
                guard !Task.isCancelled else { return }
                proxy.scrollTo(id, anchor: .top)
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .top)
            }
            // Only now — after this positioning has actually run — can the follow-scroll safely
            // start for this turn without overriding it.
            hasSettledInitialScrollFor = chatManager.streamingMessageId
        }
    }
}
