import SwiftUI

// MARK: - Requests Sidebar Context List
// Layer 3b of the sidebar for the Requests destination (P3): quick filters, then the
// last few requests the user opened. Tapping either lands on the Requests list — a
// filter applies to it, a recent request is pushed onto its stack.

struct RequestsSidebarList: View {
    @ObservedObject var state: RequestsState
    @ObservedObject var recents: RecentRequestsStore
    let onSelectFilter: (RequestsQuickFilter) -> Void
    let onOpenRecent: (RecentRequest) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                SidebarSectionHeader(title: "Filters")
                if let model = state.changeRequests {
                    QuickFilterRows(model: model, onSelect: onSelectFilter)
                }

                SidebarSectionHeader(title: "Recently viewed")
                if recents.items.isEmpty {
                    Text("Requests you open show up here.")
                        .font(BFFont.sidebarMeta)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                } else {
                    ForEach(recents.items) { recent in
                        RecentRequestRow(recent: recent) { onOpenRecent(recent) }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
    }
}

/// Holds the list model as `@ObservedObject` so the selected filter follows changes made
/// in the list's own filter sheet.
private struct QuickFilterRows: View {
    @ObservedObject var model: ChangeRequestListViewModel
    let onSelect: (RequestsQuickFilter) -> Void

    var body: some View {
        ForEach(RequestsQuickFilter.allCases) { filter in
            QuickFilterRow(filter: filter, isSelected: model.activeQuickFilter == filter) {
                onSelect(filter)
            }
        }
    }
}

private struct QuickFilterRow: View {
    let filter: RequestsQuickFilter
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var background: Color {
        if isSelected { return BFColor.primary.opacity(0.15) }
        if isHovered { return BFColor.rowHover }
        return Color.primary.opacity(0.0001)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                marker
                    .frame(width: 16)
                Text(filter.title)
                    .font(isSelected ? BFFont.sidebarItemMed : BFFont.sidebarItem)
                    .foregroundStyle(isSelected ? BFColor.primary : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(background, in: RoundedRectangle(cornerRadius: BFRadius.row, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("sidebar.requests.filter.\(filter.id)")
        .animation(BFMotion.easingDefault, value: isHovered)
        .onHover { isHovered = $0 }
        .bfPointerHover()
    }

    @ViewBuilder
    private var marker: some View {
        switch filter {
        case .all:
            Image(systemName: "tray.full").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        case .mine:
            Image(systemName: "person").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        case .status(let status):
            Circle().fill(status.style.mark).frame(width: 7, height: 7)
        }
    }
}

private struct RecentRequestRow: View {
    let recent: RecentRequest
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recent.number)
                    .font(BFFont.sidebarMeta.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(recent.title)
                    .font(BFFont.sidebarItem)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                isHovered ? BFColor.rowHover : Color.primary.opacity(0.0001),
                in: RoundedRectangle(cornerRadius: BFRadius.row, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.requests.recent.\(recent.id)")
        .animation(BFMotion.easingDefault, value: isHovered)
        .onHover { isHovered = $0 }
        .bfPointerHover()
    }
}
