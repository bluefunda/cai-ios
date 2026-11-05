import SwiftUI

// MARK: - BlueRequests Settings
// trm-ios's SettingsView profile part, as one category in cai's Settings: the
// notification preference, plus the department, role and team that only live on the
// trm side. Only listed when the Requests space is available (SettingsView filters it).

struct RequestsSettingsSection: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.requestsServices) private var services
    @StateObject private var box = ProfileBox()

    var body: some View {
        List {
            if let model = box.model {
                RequestsProfileRows(model: model)
            } else if services == nil || authManager.currentUser == nil {
                Text("BlueRequests isn't available for this account.")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("BlueRequests")
        .settingsInlineTitle()
        .task {
            guard box.model == nil, let services, let userId = authManager.currentUser?.id else { return }
            let model = ProfileViewModel(service: services.profileService, userId: userId)
            box.model = model
            await model.load()
        }
    }

    private final class ProfileBox: ObservableObject {
        @Published var model: ProfileViewModel?
    }
}

private struct RequestsProfileRows: View {
    @ObservedObject var model: ProfileViewModel

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { model.notificationsEnabled },
                set: { newValue in Task { await model.setNotificationsEnabled(newValue) } }
            )) {
                Label("Request notifications", systemImage: "bell")
                    #if targetEnvironment(macCatalyst)
                    .font(MacSettingsFont.row)
                    #endif
            }
            .disabled(model.profile == nil)
            .bfPointerHover()
            .accessibilityIdentifier("settings.requests.notifications")
        } footer: {
            Text("Whether BlueRequests notifies you about changes and comments on your requests.")
                #if targetEnvironment(macCatalyst)
                .font(MacSettingsFont.secondary)
                #endif
        }

        Section("Your profile") {
            if model.isLoading && model.profile == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let error = model.error, model.profile == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        model.error = nil
                        Task { await model.load() }
                    }
                    .bfPointerHover()
                }
            } else {
                row("Department", value: model.profile?.department)
                row("Role", value: model.profile?.role)
                row("Team", value: model.profile?.teamName)
            }
        }
    }

    private func row(_ label: String, value: String?) -> some View {
        LabeledContent(label) {
            Text(value.flatMap { $0.isBlank ? nil : $0 } ?? "Not set")
                .foregroundStyle(.secondary)
        }
        #if targetEnvironment(macCatalyst)
        .font(MacSettingsFont.row)
        #endif
    }
}
