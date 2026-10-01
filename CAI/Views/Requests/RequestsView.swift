import SwiftUI

// MARK: - Requests Content
// The Requests workspace body (bluerequests: Change Requests / Projects /
// Releases). The shell (AppShell) provides the top bar and the shared
// sidebar; this view only renders the section picker + list content.

struct RequestsContent: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject var manager: RequestsManager
    @State private var section: RequestsManager.Section = .changeRequests

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                ForEach(RequestsManager.Section.allCases) { s in
                    Text(s.title).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            sectionContent
        }
        .task(id: section) {
            manager.configure(authManager: authManager)
            await manager.refresh(section)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        if manager.isLoading && manager.isEmpty(section) {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = manager.error, manager.isEmpty(section) {
            RequestsErrorState(message: error) {
                Task { await manager.refresh(section) }
            }
        } else if manager.isEmpty(section) {
            RequestsEmptyState(section: section)
        } else {
            List {
                switch section {
                case .changeRequests:
                    ForEach(manager.changeRequests) { ChangeRequestRow(cr: $0) }
                case .projects:
                    ForEach(manager.projects) { ProjectRow(project: $0) }
                case .releases:
                    ForEach(manager.releases) { ReleaseRow(release: $0) }
                }
            }
            .listStyle(.plain)
            .refreshable { await manager.refresh(section) }
        }
    }
}

// MARK: - Rows

private struct ChangeRequestRow: View {
    let cr: ChangeRequestDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(cr.shortDescription ?? cr.description ?? "Untitled Change Request")
                .font(BFFont.bodyMedium)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let status = cr.status {
                    StatusBadge(text: status.title, color: statusColor(status))
                }
                if let requestId = cr.requestId {
                    Text(requestId)
                        .font(BFFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ status: ChangeRequestStatus) -> Color {
        switch status {
        case .planned: return BFColor.info
        case .inprogress: return BFColor.warning
        case .completed: return BFColor.success
        case .blocked: return BFColor.error
        }
    }
}

private struct ProjectRow: View {
    let project: ProjectDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(BFFont.bodyMedium)

            HStack(spacing: 8) {
                if let type = project.projectType {
                    Text(type)
                        .font(BFFont.caption)
                        .foregroundStyle(.secondary)
                }
                if let count = project.requestCount {
                    Text("\(count) request\(count == 1 ? "" : "s")")
                        .font(BFFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ReleaseRow: View {
    let release: ReleaseDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(release.description ?? release.changeRequestId)
                .font(BFFont.bodyMedium)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let status = release.status {
                    StatusBadge(text: status.capitalized, color: BFColor.info)
                }
                if let planned = release.plannedOn {
                    Text(planned)
                        .font(BFFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(BFFont.micro.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Empty / Error States

private struct RequestsEmptyState: View {
    let section: RequestsManager.Section

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No \(section.title.lowercased()) yet")
                .font(BFFont.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RequestsErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(BFColor.error)
            Text(message)
                .font(BFFont.bodySmall)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry", action: retry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Requests Top Bar (iPhone only — iPad/Mac use .toolbar items, see AppShell)

struct RequestsTopBar: View {
    @Binding var sidebarOpen: Bool

    var body: some View {
        HStack(spacing: 14) {
            HamburgerButton(sidebarOpen: $sidebarOpen)

            Text("Requests")
                .font(BFFont.h5)

            Spacer()
        }
        .padding(.horizontal, BFSpacing._4)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }
}

#Preview {
    RequestsContent(manager: RequestsManager())
        .environmentObject(AuthManager())
}
