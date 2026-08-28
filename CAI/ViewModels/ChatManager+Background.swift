import Foundation
import UIKit

// MARK: - Background / Foreground Reconciliation
// Split from the main ChatManager body to stay under SwiftLint's
// file_length limit (bluefunda/cai-ios#261) — file_length is measured per
// file, unlike type_body_length, so an extension needs its own file to help.

extension ChatManager {

    /// UserDefaults key backing `restoreLastConversation()` below.
    static let lastConversationIDKey = "cai_last_conversation_id"

    /// Reselects whichever conversation was active last time, so the app
    /// reopens where the user left off instead of always showing the
    /// greeting screen (bluefunda/cai-ios#261). No-ops if nothing was saved,
    /// a conversation is already active (e.g. a warm resume that never lost
    /// `currentConversation` in the first place), or the saved id no longer
    /// matches anything in the freshly-loaded chat list (deleted, or was
    /// never more than an unsent draft).
    func restoreLastConversation() {
        guard currentConversation == nil,
              let lastID = UserDefaults.standard.string(forKey: Self.lastConversationIDKey),
              let match = conversations.first(where: { $0.id == lastID }) else { return }
        selectConversation(match)
    }

    /// Requests OS run time so a response already generating can finish even
    /// if the app is backgrounded moments later. This is a short, best-effort
    /// grace window (typically ~30s, entirely OS-controlled) — long
    /// responses will still outlive it, which is what
    /// `reconcileAfterBackground()` below is for.
    func beginStreamBackgroundTask() {
        guard streamBackgroundTask == .invalid else { return }
        streamBackgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "ChatStreamCompletion"
        ) { [weak self] in
            self?.endStreamBackgroundTask()
        }
    }

    func endStreamBackgroundTask() {
        guard streamBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(streamBackgroundTask)
        streamBackgroundTask = .invalid
    }

    /// Called by CAIApp when the scene backgrounds — if a response is still
    /// streaming, remember its conversation so it can be reconciled with the
    /// server's copy on return to foreground (bluefunda/cai-ios#261).
    func noteBackgrounding() {
        guard isStreaming, let id = currentConversation?.id else { return }
        interruptedStreamConversationID = id
    }

    /// Called by CAIApp when the scene becomes active. Generation continues
    /// server-side regardless of whether the client's stream connection
    /// survived backgrounding, so if one was interrupted, re-fetch that
    /// conversation's messages from the server rather than leaving whatever
    /// content the reveal ticker last painted (bluefunda/cai-ios#261).
    func reconcileAfterBackground() async {
        guard let id = interruptedStreamConversationID else { return }
        interruptedStreamConversationID = nil

        // The interrupted stream's Task is suspended, not finished, if it's
        // still "streaming" here — freezing with the process rather than
        // completing or erroring out. Left alone, it resumes the instant the
        // process does, and its now-dead connection throws moments later;
        // that resumed task would then overwrite (sometimes with nothing —
        // an empty ChatMessage(content:) — flipping the whole screen back to
        // the empty/new-chat state) the authoritative content the fetch
        // below is about to load. Cancelling first makes it a clean no-op:
        // every content-writing branch downstream of the network loop is
        // already guarded on `!Task.isCancelled`.
        if isStreaming {
            streamingTask?.cancel()
            streamingTask = nil
            isStreaming = false
            endStreamBackgroundTask()
        }

        await loadMessages(for: id, force: true)
    }
}
