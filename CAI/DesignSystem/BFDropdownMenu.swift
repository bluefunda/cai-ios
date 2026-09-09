import SwiftUI

/// One row in a `BFDropdownMenu`.
struct BFDropdownRow: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let action: () -> Void

    init(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }
}

/// A custom SwiftUI-rendered dropdown (a trigger Button + `.popover`) — NOT a drop-in Menu
/// replacement, and deliberately not used for every Menu in the app. `Menu`'s content becomes
/// native system menu items once opened on Mac Catalyst, entirely outside SwiftUI's live view
/// tree, so a real `UIPointerInteraction` (`bfPointerHover()`) can never attach to those rows —
/// confirmed via live-device testing (bluefunda/cai-ios#292/#293) showing zero hover feedback on
/// Menu items despite `bfPointerHover()` being applied to them. Each row here stays a live
/// SwiftUI Button instead, so hover actually works.
///
/// Scoped ONLY to the profile menu (ContentView.swift) — NOT ModeModelPicker or
/// PersonaComposerControl (ComposerPickers.swift) or the attach menu (ChatInputView.swift): a
/// popover-based rebuild of those specific components previously regressed mouse-click
/// reliability on Mac Catalyst and was reverted back to Menu (cai-ios#257 follow-up, see the
/// comments in ComposerPickers.swift). The profile menu's simpler shape (a flat action list, no
/// per-item multi-select state, no Section headers) is different enough that the same regression
/// is less likely, but click behavior here should still be verified carefully on a real Mac.
struct BFDropdownMenu<TriggerLabel: View>: View {
    let rows: [BFDropdownRow]
    @ViewBuilder let label: () -> TriggerLabel

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label()
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.0001))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .bfPointerHover()
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    Button {
                        isPresented = false
                        row.action()
                    } label: {
                        HStack {
                            Label(row.title, systemImage: row.systemImage)
                            Spacer()
                        }
                        .foregroundStyle(row.role == .destructive ? Color.red : Color.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(Color.primary.opacity(0.0001))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .bfPointerHover()
                }
            }
            .padding(.vertical, 4)
            .frame(minWidth: 200)
            // Without this, a popover on a compact-width scene (iPhone) becomes a full sheet by
            // default instead of a floating popover — irrelevant on Mac Catalyst/iPad (always
            // regular width) but keeps behavior predictable if this is ever reached from iPhone.
            .presentationCompactAdaptation(.popover)
        }
    }
}
