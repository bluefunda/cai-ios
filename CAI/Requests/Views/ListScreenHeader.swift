import SwiftUI

/// The band under a Requests list's navigation bar: a search field, plus a row for the
/// screen's own controls (Requests' Active/Archive switch). Ported from trm-ios, minus
/// its title and "+" — in cai-ios those live in the native navigation bar, next to the
/// shell's sidebar control, so the title row isn't drawn twice (P6: the toolbar is per
/// destination). A custom field rather than `.searchable`, which can't be pinned into a
/// row alongside other controls.
struct ListScreenHeader<Leading: View, Trailing: View>: View {
    @Binding var searchText: String
    let searchPrompt: String
    @ViewBuilder var secondaryRowLeading: () -> Leading
    @ViewBuilder var secondaryRowTrailing: () -> Trailing

    var body: some View {
        VStack(spacing: BFSpacing._2) {
            HeaderSearchField(text: $searchText, prompt: searchPrompt)
            HStack(spacing: BFSpacing._3) {
                secondaryRowLeading()
                Spacer(minLength: BFSpacing._3)
                secondaryRowTrailing()
            }
        }
        .padding(.horizontal, BFSpacing._4)
        .padding(.top, BFSpacing._2)
        .padding(.bottom, BFSpacing._2)
        .background(BFColor.surfaceCanvas)
        .overlay(alignment: .bottom) { BFHairline() }
    }
}

extension ListScreenHeader where Leading == EmptyView, Trailing == EmptyView {
    init(searchText: Binding<String>, searchPrompt: String) {
        self.init(
            searchText: searchText,
            searchPrompt: searchPrompt,
            secondaryRowLeading: { EmptyView() },
            secondaryRowTrailing: { EmptyView() }
        )
    }
}

private struct HeaderSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .font(RQFont.body)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(BFColor.surfaceSunken, in: Capsule())
        .overlay(Capsule().strokeBorder(BFColor.hairline, lineWidth: 0.5))
    }
}
