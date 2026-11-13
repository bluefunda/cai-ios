import SwiftUI

// MARK: - Releases Destination
// Ported from trm-ios: trm web's drag-and-drop release board as a list grouped by planned
// date. Completed requests wait under "Ready to schedule"; scheduling one, or moving a
// planned release, picks the date in a sheet instead of dropping onto a column. A request
// with a platform stays on the web, which deploys it as part of scheduling.

struct ReleasesListView: View {
    @ObservedObject var state: RequestsState
    var navigationControl: ShellNavigationControl = .none

    var body: some View {
        NavigationStack {
            Group {
                if let model = state.releases {
                    ReleasesListScreen(model: model, navigationControl: navigationControl)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .shellNavigationControl(navigationControl)
                }
            }
            .navigationDestination(for: String.self) { id in
                ChangeRequestDetailView(changeRequestId: id, state: state, origin: .release)
            }
        }
    }
}

/// What the schedule sheet is for: a ready request, or a planned release to move.
private enum ScheduleTarget: Identifiable {
    case request(ChangeRequest)
    case release(RQRelease)

    var id: String {
        switch self {
        case .request(let request): return "request-\(request.id)"
        case .release(let release): return "release-\(release.changeRequestId)"
        }
    }

    var title: String {
        switch self {
        case .request(let request): return request.title
        case .release(let release): return release.title
        }
    }

    var currentDate: Date? {
        if case .release(let release) = self { return release.plannedOn }
        return nil
    }
}

private struct ReleasesListScreen: View {
    @ObservedObject var model: ReleasesListViewModel
    let navigationControl: ShellNavigationControl
    @State private var scheduling: ScheduleTarget?
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            ListScreenHeader(searchText: $model.searchText, searchPrompt: "Search releases")
            content
        }
        // One readable column on a wide window, as the other Requests screens.
        .readableColumn()
        .background(BFColor.surfaceCanvas)
        .navigationTitle("Releases")
        .navigationBarTitleDisplayMode(.inline)
        .shellNavigationControl(navigationControl)
        .task { await model.loadIfNeeded() }
        .refreshable { await model.load() }
        .sheet(item: $scheduling) { target in
            ScheduleReleaseSheet(target: target, model: model)
        }
        .sheet(isPresented: $showSettings) {
            ReleaseSettingsSheet(model: model)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Label("Release settings", systemImage: "gearshape")
                }
                .bfPointerHover()
                .accessibilityIdentifier("requests.release.settings")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.sections.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.error, model.sections.isEmpty {
            RequestsErrorCard(message: RequestsErrorCard.message(for: error, subject: "releases")) {
                Task { await model.load() }
            }
        } else if model.filteredSections.isEmpty && model.filteredReady.isEmpty {
            if model.searchText.isEmpty {
                ContentUnavailableView("Nothing scheduled yet", systemImage: "shippingbox")
            } else {
                ContentUnavailableView.search(text: model.searchText)
            }
        } else {
            List {
                if let error = model.error {
                    InlineErrorBanner(message: error) { Task { await model.load() } }
                        .listRowSeparator(.hidden)
                }
                if !model.filteredReady.isEmpty {
                    Section {
                        ForEach(model.filteredReady) { request in
                            ReadyRow(request: request, isBusy: model.isScheduling) {
                                scheduling = .request(request)
                            }
                            .listRowBackground(BFColor.surfaceCanvas)
                            .listRowSeparatorTint(BFColor.hairline)
                        }
                    } header: {
                        Text("Ready to schedule")
                            .font(RQFont.label)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }
                ForEach(model.filteredSections) { section in
                    Section {
                        ForEach(section.releases) { release in
                            RequestRowLink(id: release.changeRequestId) {
                                ReleaseRow(release: release)
                            }
                            .listRowBackground(BFColor.surfaceCanvas)
                            .listRowSeparatorTint(BFColor.hairline)
                            .swipeActions {
                                if release.status == .planned && !release.needsWebToSchedule {
                                    Button("Reschedule") { scheduling = .release(release) }
                                        .tint(BFColor.primary)
                                }
                            }
                            .contextMenu {
                                if release.status == .planned && !release.needsWebToSchedule {
                                    Button("Reschedule…", systemImage: "calendar") { scheduling = .release(release) }
                                }
                            }
                        }
                    } header: {
                        Text(sectionTitle(section.date))
                            .font(RQFont.label)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func sectionTitle(_ date: Date?) -> String {
        guard let date else { return "No planned date" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct ReleaseRow: View {
    let release: RQRelease

    private var color: Color {
        switch release.status {
        case .planned: return BFColor.statusBlueText
        case .inProgress: return BFColor.statusOrangeText
        case .released: return BFColor.statusGreenText
        case .error: return BFColor.statusRedText
        case .other: return BFColor.statusNeutralText
        }
    }

    private var fill: Color {
        switch release.status {
        case .planned: return BFColor.statusBlueFill
        case .inProgress: return BFColor.statusOrangeFill
        case .released: return BFColor.statusGreenFill
        case .error: return BFColor.statusRedFill
        case .other: return BFColor.statusNeutralFill
        }
    }

    var body: some View {
        HStack(spacing: BFSpacing._3) {
            VStack(alignment: .leading, spacing: 4) {
                if let requestId = release.requestId {
                    Text(requestId)
                        .font(RQFont.number)
                        .foregroundStyle(.secondary)
                }
                Text(release.title)
                    .font(RQFont.rowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Label(release.status.displayName, systemImage: release.status.icon)
                .font(RQFont.pill)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(fill, in: Capsule())
                .fixedSize()
        }
        .padding(.vertical, 6)
        .frame(minHeight: 52)
    }
}

/// A completed request waiting for a release date.
private struct ReadyRow: View {
    let request: ChangeRequest
    let isBusy: Bool
    let onSchedule: () -> Void

    private var needsWeb: Bool { !request.platforms.isEmpty }

    var body: some View {
        HStack(spacing: BFSpacing._3) {
            RequestRowLink(id: request.id) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.requestNumber)
                        .font(RQFont.number)
                        .foregroundStyle(.secondary)
                    Text(request.title)
                        .font(RQFont.rowTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if needsWeb {
                        Text("Has a platform: schedule it in the web app, which deploys it.")
                            .font(RQFont.meta)
                            .foregroundStyle(.secondary)
                    }
                }
                // On a Mac the row link is a ZStack, which centres its content; keep the
                // number and title on the leading edge.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 8)
            Button("Schedule", action: onSchedule)
                .buttonStyle(.bordered)
                .disabled(needsWeb || isBusy)
                .accessibilityIdentifier("requests.release.schedule")
        }
        .padding(.vertical, 6)
    }
}

private struct ScheduleReleaseSheet: View {
    let target: ScheduleTarget
    @ObservedObject var model: ReleasesListViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date()
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(target.title)
                        .font(RQFont.rowTitle)
                    if let current = target.currentDate {
                        LabeledContent("Planned for", value: current.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                Section {
                    DatePicker("Release date", selection: $day, in: Calendar.current.startOfDay(for: Date())...,
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(BFColor.statusRedText)
                    }
                }
            }
            .navigationTitle(target.currentDate == nil ? "Schedule release" : "Reschedule release")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let failure: String?
                            switch target {
                            case .request(let request): failure = await model.schedule(request, on: day)
                            case .release(let release): failure = await model.reschedule(release, to: day)
                            }
                            if let failure { error = failure } else { dismiss() }
                        }
                    } label: {
                        if model.isScheduling { ProgressView() } else { Text("Schedule") }
                    }
                    .disabled(model.isScheduling)
                    .accessibilityIdentifier("requests.release.confirm")
                }
            }
            .onAppear {
                if let current = target.currentDate, current >= Calendar.current.startOfDay(for: Date()) { day = current }
            }
        }
        .presentationDetents([.large])
    }
}

/// The web's release settings drawer: the regular cycle, and one-off release dates.
private struct ReleaseSettingsSheet: View {
    @ObservedObject var model: ReleasesListViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var cycle = RQReleaseCycle.default
    @State private var time = Date()
    @State private var customDay = Date()
    @State private var customTime = Date()
    @State private var error: String?
    @State private var notice: String?
    @State private var isLoaded = false

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Text(error).foregroundStyle(BFColor.statusRedText).font(RQFont.meta)
                }
                Section("Release cycle") {
                    Picker("Frequency", selection: $cycle.frequency) {
                        ForEach(ReleaseFrequency.allCases) { Text($0.title).tag($0) }
                    }
                    if cycle.frequency.usesWeekday {
                        Picker("Day", selection: $cycle.day) {
                            ForEach(ReleaseWeekday.allCases) { Text($0.title).tag($0) }
                        }
                    } else {
                        Picker("Day of the month", selection: $cycle.dayOfMonth) {
                            Text("Select").tag(Int?.none)
                            ForEach(1...31, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                        }
                    }
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Toggle("Retry automatically", isOn: $cycle.systemRetry)
                    if cycle.systemRetry {
                        Picker("Retries", selection: $cycle.attempts) {
                            Text("Once").tag(1)
                            Text("Twice").tag(2)
                        }
                    }
                    Toggle("Allow manual retry", isOn: $cycle.manualRetry)
                    Button("Save release cycle") {
                        Task { await saveCycle() }
                    }
                    .disabled(model.isScheduling || !isLoaded)
                    .accessibilityIdentifier("requests.release.saveCycle")
                }

                Section {
                    DatePicker("Date", selection: $customDay, in: Calendar.current.startOfDay(for: Date())...,
                               displayedComponents: .date)
                    DatePicker("Time", selection: $customTime, displayedComponents: .hourAndMinute)
                    Button("Add release date") {
                        Task { await addCustom() }
                    }
                    .disabled(model.isScheduling)
                    .accessibilityIdentifier("requests.release.addCustom")
                    ForEach(model.customReleases) { release in
                        if let date = release.date {
                            LabeledContent(date.formatted(date: .abbreviated, time: .omitted),
                                           value: release.time.map { String(format: "%02d:%02d", $0.hour, $0.minute) } ?? "")
                        }
                    }
                } header: {
                    Text("Custom releases")
                } footer: {
                    Text("A one-off release date, in addition to the regular cycle.")
                }
                if let notice {
                    Text(notice).font(RQFont.meta).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Release settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                error = await model.loadSettings()
                if let loaded = model.releaseCycle {
                    cycle = loaded
                    if cycle.attempts < 1 { cycle.attempts = 1 }
                    time = (loaded.time ?? ReleaseTime(hour: 18, minute: 0)).date()
                }
                isLoaded = true
            }
        }
    }

    private func saveCycle() async {
        var updated = cycle
        updated.time = ReleaseTime(time)
        error = await model.saveReleaseCycle(updated)
        notice = error == nil ? "Release cycle saved." : nil
    }

    private func addCustom() async {
        error = await model.addCustomRelease(on: customDay, at: ReleaseTime(customTime))
        notice = error == nil ? "Release date added." : nil
    }
}
