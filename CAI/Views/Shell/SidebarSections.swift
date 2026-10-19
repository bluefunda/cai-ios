import SwiftUI

// Pieces of SidebarView, split out to keep each file readable. All of them are
// sidebar-only and assume `BFColor.surfaceSidebar` behind them.

// MARK: - Space Switcher

/// Two-segment control at the top of the sidebar (P2). The selected segment is filled
/// Deep Blue — `secondaryAdaptive`, the structure colour — not the Happy Blue accent,
/// which stays reserved for tappable details (P13). Only shown when the user has
/// more than one space.
struct SpaceSwitcher: View {
    let spaces: [AppSpace]
    let selection: AppSpace
    let onSelect: (AppSpace) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(spaces) { space in
                SpaceSegment(space: space, isSelected: space == selection) {
                    onSelect(space)
                }
            }
        }
        .padding(2)
        .background(BFColor.surfaceSunken, in: Capsule())
        .overlay(Capsule().strokeBorder(BFColor.hairline, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Space")
    }
}

private struct SpaceSegment: View {
    let space: AppSpace
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var fill: Color {
        if isSelected { return BFColor.secondaryAdaptive }
        if isHovered { return BFColor.rowHover }
        return .clear
    }

    var body: some View {
        Button(action: action) {
            Text(space.title)
                .font(isSelected ? BFFont.sidebarItemMed : BFFont.sidebarItem)
                .foregroundStyle(isSelected ? BFColor.surfaceCanvas : Color.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(fill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("sidebar.space.\(space.rawValue)")
        .onHover { isHovered = $0 }
        .bfPointerHover()
    }
}

// MARK: - Destination Row

/// A fixed row in layer 3a. The current destination gets the brand light-blue wash
/// with Deep Blue text, distinct from the selected-conversation highlight below it:
/// one says where you are, the other which chat is open.
struct SidebarDestinationRow: View {
    let destination: SidebarDestination
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var background: Color {
        if isSelected { return BFColor.statusBlueFill }
        if isHovered { return BFColor.rowHover }
        return Color.primary.opacity(0.0001)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: destination.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(destination.title)
                    .font(isSelected ? BFFont.sidebarItemMed : BFFont.sidebarItem)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? BFColor.secondaryAdaptive : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(background, in: RoundedRectangle(cornerRadius: BFRadius.row, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(destination.accessibilityIdentifier)
        .animation(BFMotion.easingDefault, value: isHovered)
        .onHover { isHovered = $0 }
        .bfPointerHover()
    }
}

// MARK: - SAP Systems (Code's context list)

/// The registered SAP systems; tapping one makes it the active system Code browses.
struct SidebarSystemsList: View {
    @ObservedObject var store: SAPSystemStore
    let onManage: () -> Void
    let onSelect: (SAPSystem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                SidebarSectionHeader(title: "SAP systems")
                ForEach(store.systems) { system in
                    SystemRow(system: system, isActive: store.activeSystemID == system.id) {
                        store.activeSystemID = system.id
                        onSelect(system)
                    }
                }
                ManageSystemsRow(hasSystems: !store.systems.isEmpty, action: onManage)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
    }
}

private struct SystemRow: View {
    let system: SAPSystem
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var background: Color {
        if isActive { return BFColor.primary.opacity(0.15) }
        if isHovered { return BFColor.rowHover }
        return Color.primary.opacity(0.0001)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(system.name)
                    .font(isActive ? BFFont.sidebarItemMed : BFFont.sidebarItem)
                    .foregroundStyle(isActive ? BFColor.primary : Color.primary)
                    .lineLimit(1)
                Text("\(system.username) on client \(system.client)")
                    .font(BFFont.sidebarMeta)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(background, in: RoundedRectangle(cornerRadius: BFRadius.row, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier("sidebar.system.\(system.id.uuidString)")
        .animation(BFMotion.easingDefault, value: isHovered)
        .onHover { isHovered = $0 }
        .bfPointerHover()
    }
}

private struct ManageSystemsRow: View {
    let hasSystems: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: hasSystems ? "slider.horizontal.3" : "plus")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(hasSystems ? "Manage systems" : "Add a SAP system")
                    .font(BFFont.sidebarItem)
                Spacer(minLength: 0)
            }
            .foregroundStyle(BFColor.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isHovered ? BFColor.rowHover : Color.primary.opacity(0.0001),
                in: RoundedRectangle(cornerRadius: BFRadius.row, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.manageSystems")
        .animation(BFMotion.easingDefault, value: isHovered)
        .onHover { isHovered = $0 }
        .bfPointerHover()
    }
}

// MARK: - Section Header

/// Sentence case, quiet — "Pinned", "Today", "SAP systems" (P13 copy rules; the old
/// tracked-out uppercase labels read as louder than the rows they introduce).
struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(BFFont.sidebarSection)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Organization Chip

/// The signed-in user's effective Keycloak org, beside their email in the profile row,
/// so it's clear which workspace the app is acting in.
struct OrganizationChip: View {
    let alias: String

    var body: some View {
        Text(alias)
            .font(BFFont.sidebarMeta.weight(.medium))
            .foregroundStyle(BFColor.secondaryAdaptive)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(BFColor.statusBlueFill, in: Capsule())
            .fixedSize()
            .accessibilityLabel("Organization \(alias)")
    }
}
