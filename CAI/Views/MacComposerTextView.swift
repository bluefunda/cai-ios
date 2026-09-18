#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

// Mac Catalyst-only. SwiftUI's `.onKeyPress` never sees the Return key on a
// multi-line (axis: .vertical) TextField — confirmed live, adding it had zero
// effect — because the underlying UITextView claims a bare Return for its own
// "insert newline" text-input handling before SwiftUI's key-press delivery ever
// runs. The only reliable intercept point is UIKit's own `keyCommands`, which a
// UIKeyCommand registered directly on the first-responder view DOES take
// priority over that default text-insertion pathway for — the same mechanism
// apps like Slack/Notion use for "Return sends, Shift+Return inserts a newline"
// on a hardware keyboard. This file swaps the composer's TextField for a real
// UITextView on Mac Catalyst only; iOS/iPadOS keep the ordinary TextField in
// ChatInputView.swift, where soft-keyboard Return staying "insert newline" is
// the expected behavior.

/// UITextView subclass that intercepts a bare Return key press before it can
/// reach UITextView's own newline-insertion handling. Only the *unmodified*
/// Return is registered here, so Shift+Return still falls through to the
/// default text-input pathway and inserts a newline as normal.
final class ReturnSendingTextView: UITextView {
    var onReturn: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        let plainReturn = UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(handlePlainReturn))
        return (super.keyCommands ?? []) + [plainReturn]
    }

    @objc private func handlePlainReturn() {
        onReturn?()
    }
}

struct MacComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var minLines: Int = 1
    var maxLines: Int = 5
    // Bumped by ChatView whenever `text` is changed programmatically (composer cleared after
    // send) rather than by the user typing. See the Coordinator's lastAppliedExternalUpdateToken
    // for how this replaces inferring the same thing from "the view lost focus" — that stopped
    // being a reliable signal once the composer started staying focused through send on Mac.
    var externalUpdateToken: Int = 0
    let onReturn: () -> Void

    // BFFont.body (18pt regular) resolves to this same system font in practice —
    // its custom "GeneralSans-Regular" isn't bundled (see BFTypography.swift's
    // "requires license confirmation for iOS bundle distribution" note), so the
    // fallback system font is what actually renders today.
    private var font: UIFont { .systemFont(ofSize: 18, weight: .regular) }

    func makeUIView(context: Context) -> ReturnSendingTextView {
        let textView = ReturnSendingTextView()
        textView.delegate = context.coordinator
        textView.font = font
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.textColor = .label
        textView.text = text
        return textView
    }

    func updateUIView(_ uiView: ReturnSendingTextView, context: Context) {
        uiView.onReturn = onReturn
        // Never write into the view while it's actively being typed into, UNLESS ChatView
        // has bumped externalUpdateToken — an explicit, unambiguous "this text change came
        // from outside the user's own typing" signal (e.g. the composer cleared after
        // sending). Without that signal, any unrelated SwiftUI re-render can deliver
        // `updateUIView` with a `text` snapshot that's stale by a keystroke or two, and
        // overwriting uiView.text with it silently erases whatever had just been typed. An
        // earlier version of this fix inferred "external clear" from "text went empty while
        // the view still has content" instead — indistinguishable from a stale *pre-typing*
        // empty snapshot arriving late for a message's very first character, which wiped it
        // out the exact same way. A version before that relied on "the view isn't first
        // responder" as the signal (sendMessage always resigned it before clearing) — that
        // broke once the composer started staying focused through send on Mac.
        // Strictly-greater, not just "different": a stale render can be delivered AFTER a
        // newer one already advanced the coordinator's record, and a stale render's token
        // would look "different" too if compared with != — treating that as fresh would
        // apply its equally-stale `text` right back over live typing.
        let isExternalUpdate = externalUpdateToken > context.coordinator.lastAppliedExternalUpdateToken
        if (isExternalUpdate || !uiView.isFirstResponder), uiView.text != text {
            uiView.text = text
        }
        if isExternalUpdate {
            context.coordinator.lastAppliedExternalUpdateToken = externalUpdateToken
        }
        // Only becoming focused is handled reactively here. Resigning is left entirely
        // to the explicit, synchronous UIApplication.shared.sendAction(resignFirst-
        // Responder...) calls at each real dismiss-keyboard site in ChatView.swift —
        // mirroring that reactively off `isFocused.wrappedValue` here (an earlier
        // version of this fix did, even deferred by a runloop turn) re-introduced the
        // same staleness hazard as the text sync above: a stale "false" snapshot
        // delivered right after textViewDidBeginEditing's "true" had committed kicked
        // focus straight back out after a single keystroke, forcing a re-click to type
        // the next character.
        if isFocused, uiView.window != nil, !uiView.isFirstResponder {
            if !uiView.becomeFirstResponder() {
                // On launch, the Mac Catalyst window isn't always key yet at the moment
                // ChatView's triggerFocus fires — becomeFirstResponder() silently no-ops
                // on a non-key window, and since nothing else necessarily re-renders this
                // view afterward, the composer was staying unfocused indefinitely (no
                // second attempt was ever triggered). Retry shortly against live state
                // rather than a captured snapshot, so this doesn't reintroduce the same
                // staleness hazard as the sync above.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if isFocused, !uiView.isFirstResponder {
                        uiView.becomeFirstResponder()
                    }
                }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ReturnSendingTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let lineHeight = font.lineHeight
        let minHeight = lineHeight * CGFloat(minLines)
        let maxHeight = lineHeight * CGFloat(maxLines)
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        uiView.isScrollEnabled = fitting.height > maxHeight
        return CGSize(width: width, height: min(max(fitting.height, minHeight), maxHeight))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MacComposerTextView
        // Tracks the highest externalUpdateToken seen so far — see updateUIView's comment.
        var lastAppliedExternalUpdateToken: Int
        init(_ parent: MacComposerTextView) {
            self.parent = parent
            self.lastAppliedExternalUpdateToken = parent.externalUpdateToken
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // Guarded: becomeFirstResponder() (called reactively from updateUIView when
            // isFocused went true externally) triggers this delegate callback synchronously
            // — writing the same true value back into the binding it was just read from,
            // in the same SwiftUI update pass, is what SwiftUI's AttributeGraph flagged as
            // "cycle detected" (confirmed live via debug logging: a burst of those warnings
            // appeared at exactly this moment). Only write when it's an actual change.
            if !parent.isFocused { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }
    }
}
#endif
