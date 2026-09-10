#if DEBUG
import SwiftUI

/// Debug-only harness for exercising the Tip Engine (Phases 1-5,
/// bluefunda/cai-ios#155) end-to-end with no product UI in front of it yet.
/// Reads/writes the same on-device files the real app uses (default
/// `TipEngineFileStore` paths), so this reflects genuine state — including
/// `InterestProfile` turns recorded from real chat activity via
/// `ChatManager`. Never compiled into Release builds.
struct TipEngineDebugView: View {
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var iapManager: IAPManager

    @State private var catalog = TipCatalog()
    @State private var isRefreshing = false
    @State private var antiAnnoyance = AntiAnnoyance()
    @State private var rewardLog = TipRewardLog()
    @State private var selected: TipManifestEntry?
    @State private var ranSelectionOnce = false
    /// Bumped after any action that mutates a class held in `@State` in
    /// place (AntiAnnoyance/TipRewardLog aren't ObservableObject) — SwiftUI
    /// only notices a *reassignment* of a `@State` var, not internal
    /// mutation of the reference type it holds, so this forces the
    /// re-render those sections need to reflect the mutation.
    @State private var tick = 0

    private var profile: InterestProfile { InterestProfile() }

    var body: some View {
        List {
            catalogSection
            interestProfileSection
            selectionSection
            antiAnnoyanceSection
            rewardLogSection
            resetSection
        }
        // AntiAnnoyance/TipRewardLog are plain classes mutated in place, not
        // ObservableObject — `.id(tick)` forces this List to be treated as a
        // new identity (and its body fully re-evaluated) whenever `tick`
        // changes, rather than relying on incidental @State re-render timing.
        .id(tick)
        .navigationTitle("Tip Engine Debug")
    }

    // MARK: - Catalog (Phase 2)

    private var catalogSection: some View {
        Section("Catalog") {
            HStack {
                Text("iOS-surfaced entries")
                Spacer()
                Text("\(catalog.entries.count)").foregroundStyle(.secondary)
            }
            ForEach(catalog.entries, id: \.id) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.render.ios?.title ?? entry.id).font(.subheadline.bold())
                    if let body = entry.render.ios?.body {
                        Text(body).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                Task {
                    isRefreshing = true
                    await catalog.refresh()
                    isRefreshing = false
                }
            } label: {
                HStack {
                    Text("Refresh from bluefunda/tip-catalog")
                    if isRefreshing { Spacer(); ProgressView() }
                }
            }
            .disabled(isRefreshing)
        }
    }

    // MARK: - Interest profile (Phase 1)

    private var interestProfileSection: some View {
        let vector = profile.vector()
        return Section("Interest Profile") {
            ForEach(Array(zip(TipTopic.allCases, vector)), id: \.0.rawValue) { topic, weight in
                if weight > 0.001 {
                    HStack {
                        Text(topic.rawValue)
                        Spacer()
                        Text(String(format: "%.3f", weight)).foregroundStyle(.secondary)
                    }
                }
            }
            if vector.allSatisfy({ $0 < 0.001 }) {
                Text("No signal yet. Send a chat message — or trigger an error / rate limit / persona switch — to record a turn (TurnTopicSource is a coarse placeholder, see its header comment).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Selection (Phase 3) + reward events (Phase 5)

    private var selectionSection: some View {
        Section("Selection") {
            Button("Run TipSelector.select") {
                antiAnnoyance.startSession()
                let context = TipSelectionContext(
                    personaId: (chatManager.personaEnabled ? chatManager.persona : .general).id,
                    isGeneralMode: !chatManager.personaEnabled || chatManager.persona == .general,
                    hasActiveSubscription: iapManager.hasActiveSubscription
                )
                selected = TipSelector.select(
                    from: catalog.entries, profile: profile.vector(),
                    antiAnnoyance: antiAnnoyance, context: context
                )
                ranSelectionOnce = true
                tick += 1
            }

            if let selected {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selected.render.ios?.title ?? selected.id).font(.headline)
                    if let body = selected.render.ios?.body {
                        Text(body).font(.subheadline)
                    }
                }
                HStack {
                    Button("Record Shown") {
                        antiAnnoyance.recordShown(tipId: selected.id, family: selected.family)
                        rewardLog.log(.shown, tipId: selected.id, catalogVersion: selected.catalogVersion, interestVector: profile.vector())
                        tick += 1
                    }
                    Button("Tapped") {
                        antiAnnoyance.recordTapped(tipId: selected.id)
                        rewardLog.log(.tapped, tipId: selected.id, catalogVersion: selected.catalogVersion, interestVector: profile.vector())
                        tick += 1
                    }
                    Button("Dismissed") {
                        antiAnnoyance.recordDismissed(family: selected.family)
                        rewardLog.log(.dismissed, tipId: selected.id, catalogVersion: selected.catalogVersion, interestVector: profile.vector())
                        tick += 1
                    }
                }
                .buttonStyle(.bordered)
            } else if ranSelectionOnce {
                Text("No eligible tip (see Anti-Annoyance State below, and the catalog above — the published catalog only has 2 placeholder tips today).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Anti-annoyance state (Phase 4)

    private var antiAnnoyanceSection: some View {
        Section("Anti-Annoyance State") {
            HStack { Text("Session shown"); Spacer(); Text("\(antiAnnoyance.state.sessionShownCount) / \(AntiAnnoyance.maxPerSession)").foregroundStyle(.secondary) }
            HStack { Text("Day shown"); Spacer(); Text("\(antiAnnoyance.state.dayShownCount) / \(AntiAnnoyance.maxPerDay)").foregroundStyle(.secondary) }
            HStack { Text("Opted out"); Spacer(); Text(antiAnnoyance.isOptedOut ? "Yes" : "No").foregroundStyle(.secondary) }
            ForEach(antiAnnoyance.state.dismissals.keys.sorted(), id: \.self) { family in
                if let dismissal = antiAnnoyance.state.dismissals[family] {
                    HStack {
                        Text(family)
                        Spacer()
                        Text(dismissalDescription(dismissal)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(antiAnnoyance.state.impressions.keys.sorted(), id: \.self) { tipId in
                if let impression = antiAnnoyance.state.impressions[tipId] {
                    HStack {
                        Text(tipId)
                        Spacer()
                        Text("shown \(impression.shownCount)x, tapped: \(impression.tapped ? "yes" : "no")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func dismissalDescription(_ dismissal: FamilyDismissal) -> String {
        guard let until = dismissal.until else { return "stage \(dismissal.stage), permanent" }
        return "stage \(dismissal.stage), until \(until.formatted(date: .abbreviated, time: .shortened))"
    }

    // MARK: - Reward log (Phase 5)

    private var rewardLogSection: some View {
        Section("Reward Log (\(rewardLog.records.count) total)") {
            ForEach(Array(rewardLog.records.suffix(10).reversed().enumerated()), id: \.offset) { _, record in
                HStack {
                    Text(record.event.rawValue)
                    Spacer()
                    Text(record.tipId).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Reset

    private var resetSection: some View {
        Section {
            Button("Reset All Tip Engine State", role: .destructive) {
                let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                try? FileManager.default.removeItem(at: support.appendingPathComponent("TipEngine", isDirectory: true))
                catalog = TipCatalog()
                antiAnnoyance = AntiAnnoyance()
                rewardLog = TipRewardLog()
                selected = nil
                ranSelectionOnce = false
                tick += 1
            }
        } footer: {
            Text("Deletes interest_profile.json, anti_annoyance.json, and reward_log.json from Application Support/TipEngine.")
        }
    }
}
#endif
