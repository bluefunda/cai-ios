import SwiftUI

// MARK: - Scroll Management
// Split from ChatView's main body to stay under SwiftLint's type_body_length/file_length limits
// (bluefunda/cai-ios#261 precedent — see ChatManager+Background.swift). file_length is measured
// per file, unlike type_body_length, so an extension needs its own file to help either.

extension ChatView {

    /// Whether the "bottom" sentinel (tracked via BottomSentinelYKey) has actually scrolled into
    /// view yet, given the current viewport height — lets scrollToBottom's settle loop confirm
    /// it really reached the end instead of trusting a fixed pass count that under-shoots on a
    /// wider/taller window (Mac Catalyst) needing more rows measured than a narrow iPhone screen.
    func isNearBottomSentinel(viewportHeight: CGFloat) -> Bool {
        guard let y = bottomSentinelY else { return false }
        return y <= viewportHeight + 40
    }

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
    /// - Parameter isSettled: Reports whether the "bottom" sentinel (tracked via
    ///   BottomSentinelYKey) has actually scrolled into view yet. Checked after every pass so the
    ///   loop can exit the moment it's really done instead of trusting a fixed count — how many
    ///   passes that takes isn't fixed: a wider/taller window (Mac Catalyst) has more rows visible
    ///   at once needing measurement than a narrow iPhone screen, so a count tuned for one
    ///   under-shoots on the other (confirmed via a live repro: existing conversations opened
    ///   short of their true end specifically on Mac Catalyst, not iOS). Caller resets the tracked
    ///   position to nil before starting a fresh settle so a stale reading from whatever
    ///   conversation was open before can't read as "already settled" on the very first pass.
    func scrollToBottom(proxy: ScrollViewProxy, isSettled: @escaping () -> Bool) async {
        // cai-android's actual pass interval is withFrameNanos {} — one real display frame
        // (~16ms), not an arbitrary timer — so its whole settle loop finishes in a handful of
        // milliseconds and is never perceptible. This used Task.sleep(for: .milliseconds(100))
        // per pass — 6x slower than a frame — which made a plainly visible, sluggish "taking so
        // much time" delay on every single conversation switch, not just long ones. 16ms is the
        // closest plain-SwiftUI approximation (no CADisplayLink/frame-callback API here) to that
        // same per-frame cadence.
        //
        // 60 passes (~1s) is a hard safety cap, not the expected case — both platforms settle
        // long before that in practice (iOS reliably within the first ~10, same as before this
        // became dynamic, so this is not expected to change iOS's timing at all); it only exists
        // so a case isSettled() can never satisfy (e.g. this ran before "bottom" ever laid out)
        // can't spin forever.
        for _ in 0..<60 {
            guard !Task.isCancelled else { return }
            proxy.scrollTo("bottom", anchor: .bottom)
            try? await Task.sleep(for: .milliseconds(16))
            if isSettled() { return }
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

    @ViewBuilder
    var messageScrollArea: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { outer in
                ScrollViewReader { proxy in
                    // Lets scrollToBottom's settle loop confirm it actually reached the end —
                    // see isNearBottomSentinel's own declaration (ChatView+Scroll.swift) for why.
                    let checkNearBottomSentinel: () -> Bool = { isNearBottomSentinel(viewportHeight: outer.size.height) }
                    // List (UITableView/UICollectionView-backed) replaced ScrollView + LazyVStack
                    // here — the latter's scrollTo(id:) is identity-based and can't reliably reach
                    // a row LazyVStack hasn't measured yet (only near the viewport is ever
                    // measured), which is exactly why long conversations sometimes landed short of
                    // (or, past the trailing "bottom" marker, beyond) their true end and needed
                    // manual scrolling to self-correct. List's scroll-to-row is index/identity
                    // aware at the UIKit level regardless of measurement state — the same native
                    // guarantee cai-android's LazyColumn.scrollToItem has, which this now mirrors
                    // directly instead of approximating it with retry loops and a conditionally-
                    // toggled defaultScrollAnchor.
                    List {
                        if let conversation = chatManager.currentConversation,
                           !conversation.messages.isEmpty {
                            ForEach(Array(conversation.messages.enumerated()), id: \.element.id) { index, message in
                                // The question this answer was replying to, so a shared
                                // card (bluefunda/cai-ios#197) can show both — looked up
                                // here where the surrounding list is available, since
                                // MessageView only sees a single message.
                                let precedingQuestion = index > 0 ? conversation.messages[index - 1].content : nil
                                // The isStreaming half is keyed on the specific message id
                                // (streamingMessageId), not array position — an early Stop can
                                // remove trailing messages, and without identity-matching the
                                // new "last" message (an older, already-completed response)
                                // would briefly inherit isStreaming's true value and look like
                                // it had resumed streaming. isReconciling stays position-based:
                                // reconcileAfterBackground() clears isStreaming immediately
                                // (before its retry loop even starts) to stop the dead local
                                // stream task from racing the re-fetch, so without this the
                                // still-empty assistant bubble would fall out of the streaming
                                // state and show an empty response box (and the composer's mic
                                // button instead of Stop) for the seconds reconciliation takes —
                                // and the re-fetched message may not keep the same local id.
                                let isThisMessageStreaming = (chatManager.isStreaming && message.id == chatManager.streamingMessageId)
                                    || (chatManager.isReconciling && index == conversation.messages.count - 1)
                                // Identity-based for the same reason as isThisMessageStreaming
                                // above — didStopCurrentMessage alone, matched by position,
                                // would mislabel an older message once an early Stop removes
                                // trailing ones.
                                let wasThisMessageStopped = chatManager.didStopCurrentMessage
                                    && message.id == chatManager.stoppedMessageId
                                let isLastMessage = index == conversation.messages.count - 1
                                MessageView(
                                    message: message,
                                    precedingQuestion: precedingQuestion,
                                    isThisMessageStreaming: isThisMessageStreaming,
                                    wasStopped: wasThisMessageStopped,
                                    onRevealingChanged: isLastMessage
                                        ? { chatManager.isRevealingLastMessage = $0 }
                                        : { _ in }
                                )
                                .id(message.id)
                                .background {
                                    // Tracks the streaming row's bottom edge relative to the
                                    // List's own viewport (named coordinate space, not the
                                    // window) — lets the follow-scroll below tell whether the
                                    // user is already looking at the bottom of the growing
                                    // response versus having scrolled up to reread an earlier
                                    // part of it, matching cai-android's isScrolledToEnd()-gated
                                    // auto-scroll instead of forcing the view back down regardless.
                                    if isThisMessageStreaming {
                                        GeometryReader { rowGeo in
                                            Color.clear.preference(
                                                key: StreamingRowBottomKey.self,
                                                value: rowGeo.frame(in: .named("chatScroll")).maxY
                                            )
                                        }
                                    }
                                }
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                            }
                            // Reserves room below the last message while streaming, so
                            // scrolling the user's prompt to the top of the viewport (below)
                            // has somewhere to go instead of snapping back — matches
                            // cai-android's MessageList bottom spacer.
                            if chatManager.isStreaming {
                                Color.clear.frame(height: outer.size.height * 0.65)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(Color.clear)
                            }
                        } else if chatManager.isLoadingChats && chatManager.conversations.isEmpty {
                            ProgressView()
                                .padding(.top, 40)
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        } else {
                            EmptyStateView(greeting: greetingText)
                                // A List row sizes to its own content — unlike a plain
                                // ScrollView+VStack child, it does NOT stretch to fill the List's
                                // visible height on its own. A bare minHeight: 300 left this row
                                // sitting at the top of the List with its own internal Spacers
                                // centering only within that 300pt, not the real viewport — barely
                                // visible on a short iPhone screen, but on Mac Catalyst's much
                                // taller window it left a large dead gap below a clearly
                                // off-center greeting. Matching the actual viewport height here
                                // (still floored at 300 for a very short window) lets those
                                // Spacers center within the real available space.
                                .frame(maxWidth: .infinity, minHeight: max(outer.size.height, 300))
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                            .background {
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: BottomSentinelYKey.self,
                                        value: geo.frame(in: .named("chatScroll")).minY
                                    )
                                }
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: maxChatWidth)
                    .frame(maxWidth: .infinity)
                    .coordinateSpace(name: "chatScroll")
                    .scrollDismissesKeyboard(.interactively)
                    //
                    // Mirrors cai-android's MessageList exactly, which pairs two effects:
                    // 1) `LaunchedEffect(messages.isNotEmpty())` — the instant, unanimated
                    //    `scrollToItem(lastIndex)` fired once when the list first goes from
                    //    empty to non-empty (EmptyStateView -> real rows). This is the piece
                    //    iOS was missing: without it, the very first send left the ScrollView
                    //    at its just-created top-of-content position while the animated .top
                    //    scroll below tried to align a row that didn't have settled geometry
                    //    yet, so it visually landed under the header and snapped down once
                    //    layout caught up.
                    // 2) `LaunchedEffect(latestUserMessageId)` — the animated `.top` scroll to
                    //    the newest user row, unconditionally, first message included. Once (1)
                    //    has already forced a layout pass by aligning the last row (here, the
                    //    empty assistant placeholder) to the top, this animated step is just a
                    //    one-row correction up to the user's own message, not a fresh scroll
                    //    into unmeasured content.
                    .onChange(of: hasMessages) { _, isNonEmpty in
                        // A single un-retried scrollTo here (unlike every other scroll path,
                        // which uses the settle loop below) meant the very first message in a
                        // brand-new conversation could land with its top edge cut off under the
                        // header instead of properly positioned — this is the first time List
                        // has ever had real rows to lay out, same unmeasured-content race the
                        // settle loop exists to cover everywhere else.
                        guard isNonEmpty else { return }
                        // Cancelling scrollSettleTask here can land on an in-flight conversation-
                        // switch task (.onAppear / currentConversation.id below) before it reaches
                        // its own `isSwitchingConversation = false` — cooperative cancellation
                        // means that task's remaining code (including that reset) never runs, so
                        // without clearing it here too the loading overlay is left stuck on
                        // forever. Real content is about to render regardless, so it's always
                        // correct to drop it at this point.
                        chatManager.isSwitchingConversation = false
                        bottomSentinelY = nil
                        scrollSettleTask?.cancel()
                        scrollSettleTask = Task { @MainActor in
                            await scrollToBottom(proxy: proxy, isSettled: checkNearBottomSentinel)
                        }
                    }
                    // reconcileAfterBackground() re-fetches the conversation from the server and
                    // replaces the whole messages array with server-assigned message ids —
                    // different from the client-side ids used while the message was actively
                    // streaming. ForEach(id: \.element.id) treats that as an entirely new list
                    // (not "one row appended" like the steady-state case below), so it needs the
                    // same instant bottom-align settle as the very-first-message transition above —
                    // without it, the animated per-message scroll targets a row whose layout
                    // hasn't been established under the new identities yet, leaving the user's
                    // own prompt scrolled off above the header until something else nudges it.
                    .onChange(of: chatManager.isReconciling) { wasReconciling, isReconciling in
                        guard wasReconciling, !isReconciling,
                               let lastID = chatManager.currentConversation?.messages.last?.id else { return }
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                    .onChange(of: latestUserMessageID) { _, newID in
                        // Runs unconditionally, first message included — matching cai-android's
                        // LaunchedEffect(latestUserMessageId) exactly (see the comment above this
                        // block). A prior version skipped this for the very first message on the
                        // assumption its "natural" top offset was already correct, but that offset
                        // comes from scrollToBottom's anchor: .bottom on the "bottom" sentinel —
                        // once isStreaming reserves its 65%-height spacer ahead of that sentinel,
                        // anchoring there pushes the actual (short) message content off-screen
                        // above, leaving the spacer's blank space visible below: the prompt reads
                        // as cut off under the header on a cold launch + first message.
                        guard let newID else { return }
                        scheduleNewPromptPositioning(id: newID, proxy: proxy)
                    }
                    // Keeps a growing response from disturbing wherever the user has scrolled to —
                    // see streamingContentBucket's declaration for why this is needed at all (a
                    // growing off-screen row in SwiftUI's List isn't as inert as in cai-android's
                    // LazyColumn). Gated on hasSettledInitialScrollFor so it never fires before
                    // this turn's "scroll the new prompt to the top" positioning above has had its
                    // own chance to run — starting earlier would just override that with an
                    // unwanted scroll to the bottom instead.
                    .onChange(of: streamingContentBucket) { _, _ in
                        guard chatManager.isStreaming,
                              let id = chatManager.streamingMessageId,
                              hasSettledInitialScrollFor == id
                        else { return }
                        // Only auto-follow if the user hasn't scrolled away from the bottom of
                        // the growing response to reread an earlier part of it — matches
                        // cai-android's isScrolledToEnd()-gated auto-scroll. Without this, any
                        // manual scroll-up mid-stream got yanked back down on every ~20-char
                        // growth tick regardless of what the user was doing.
                        let viewportBottom = outer.size.height
                        let scrollAwayTolerance: CGFloat = 80
                        if let rowBottomY = streamingRowBottomY,
                           rowBottomY > viewportBottom + scrollAwayTolerance {
                            return
                        }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                    .onPreferenceChange(StreamingRowBottomKey.self) { streamingRowBottomY = $0 }
                    .onPreferenceChange(BottomSentinelYKey.self) { bottomSentinelY = $0 }
                    .onChange(of: chatManager.currentConversation?.id) { _, _ in
                        // Guarded on hasMessages: for a brand-new empty conversation (New Chat),
                        // there's nothing below the EmptyStateView but its "bottom" spacer —
                        // scrolling to it anchors that spacer at the viewport's bottom edge and
                        // pushes the ~300pt-tall greeting entirely above the visible area, reading
                        // as a blank screen until the user manually scrolls up to find it.
                        guard hasMessages else { return }
                        chatManager.isSwitchingConversation = true
                        bottomSentinelY = nil
                        scrollSettleTask?.cancel()
                        scrollSettleTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(50))
                            await scrollToBottom(proxy: proxy, isSettled: checkNearBottomSentinel)
                            // Guards against a cancelled/superseded task's cooperative-cancellation
                            // remnant (scrollToBottom returns early but this task's own code after
                            // it keeps running) clobbering the *new* task's isSwitchingConversation =
                            // true with a stale false once it finally gets scheduled.
                            guard !Task.isCancelled else { return }
                            chatManager.isSwitchingConversation = false
                        }
                    }
                    .onAppear {
                        scrollProxy = proxy
                        guard hasMessages else { return }
                        chatManager.isSwitchingConversation = true
                        bottomSentinelY = nil
                        scrollSettleTask?.cancel()
                        scrollSettleTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(50))
                            await scrollToBottom(proxy: proxy, isSettled: checkNearBottomSentinel)
                            // Guards against a cancelled/superseded task's cooperative-cancellation
                            // remnant (scrollToBottom returns early but this task's own code after
                            // it keeps running) clobbering the *new* task's isSwitchingConversation =
                            // true with a stale false once it finally gets scheduled.
                            guard !Task.isCancelled else { return }
                            chatManager.isSwitchingConversation = false
                        }
                    }
                }
            }
            if chatManager.isSwitchingConversation {
                // Covers the List (still fully mounted and doing its real layout/scroll work
                // underneath — hiding it here doesn't touch that) with a plain, unanimated
                // loading state instead of leaving the previous conversation's stale content (or
                // a mid-settle jump) visible while a long response's layout catches up. No
                // animation/opacity fade on the List itself — that's what made an earlier version
                // of this fix feel *slower*, since animating a whole List fighting for the same
                // render time as its own layout work read as the UI hanging rather than settling.
                Color(uiColor: .systemBackground)
                    .overlay(ProgressView())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
        }
    }
}
