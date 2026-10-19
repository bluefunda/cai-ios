import SwiftUI

/// The board view for Requests — the already-fetched, already-filtered list grouped by
/// status into side-by-side columns that reflow with the width (e.g. the sidebar
/// collapsing). Always shows all four of trm's own Kanban columns, even empty ones, so
/// the board keeps its shape; plus an "Other" column only when a non-standard status is
/// present. Ported from trm-ios and restyled: hairline-bordered columns, no card shadows
/// (P13 keeps everything around the stage rail quiet).
struct ChangeRequestGridView: View {
    let requests: [ChangeRequest]

    private enum ColumnKey: Hashable {
        case status(ChangeRequestStatus)
        case other
    }

    private struct Column: Identifiable {
        let key: ColumnKey
        let title: String
        let mark: Color
        let requests: [ChangeRequest]
        var id: ColumnKey { key }
    }

    private var columns: [Column] {
        let grouped = Dictionary(grouping: requests) { request -> ColumnKey in
            switch request.status {
            case .other: return .other
            default: return .status(request.status)
            }
        }
        var result = ChangeRequestStatus.allCases.map { status in
            Column(
                key: .status(status),
                title: status.style.label,
                mark: status.style.mark,
                requests: grouped[.status(status)] ?? []
            )
        }
        if let other = grouped[.other] {
            result.append(Column(key: .other, title: "Other", mark: BFColor.neutral400, requests: other))
        }
        return result
    }

    var body: some View {
        HStack(alignment: .top, spacing: BFSpacing._3) {
            ForEach(columns) { column in
                BoardColumn(title: column.title, mark: column.mark, requests: column.requests)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, BFSpacing._4)
        .padding(.vertical, BFSpacing._3)
        .background(BFColor.surfaceCanvas)
    }
}

private struct BoardColumn: View {
    let title: String
    let mark: Color
    let requests: [ChangeRequest]

    var body: some View {
        VStack(alignment: .leading, spacing: BFSpacing._2) {
            HStack(spacing: 6) {
                Circle().fill(mark).frame(width: 7, height: 7)
                Text(title)
                    .font(RQFont.rowTitle)
                    .foregroundStyle(.primary)
                Text("\(requests.count)")
                    .font(RQFont.meta)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, BFSpacing._2)
            .padding(.top, BFSpacing._2)

            if requests.isEmpty {
                Text("No requests")
                    .font(RQFont.meta)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, BFSpacing._4)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: BFSpacing._2) {
                        ForEach(requests) { request in
                            NavigationLink(value: request.id) {
                                BoardCard(request: request)
                            }
                            .buttonStyle(.plain)
                            .bfPointerHover()
                            .accessibilityIdentifier("requests.crRow.\(request.id)")
                        }
                    }
                    .padding(.horizontal, BFSpacing._2)
                    .padding(.bottom, BFSpacing._2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(BFColor.surfaceSunken.opacity(0.5), in: RoundedRectangle(cornerRadius: BFRadius.xl, style: .continuous))
    }
}

private struct BoardCard: View {
    let request: ChangeRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(request.requestNumber)
                .font(RQFont.number)
                .foregroundStyle(.secondary)
            Text(request.title)
                .font(RQFont.rowTitle)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            HStack(spacing: 6) {
                StageRail(stage: request.stage, totalStages: request.totalStages, status: request.status)
                if let severity = request.severity, !severity.isBlank {
                    PriorityPill(text: severity)
                }
                Spacer(minLength: 4)
                OwnerBadge(name: request.createdByName, avatarURLString: request.createdByAvatarURL, showsName: false)
            }
        }
        .padding(BFSpacing._3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BFColor.surfaceRaised, in: RoundedRectangle(cornerRadius: BFRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BFRadius.lg, style: .continuous)
                .strokeBorder(BFColor.hairline, lineWidth: 0.5)
        )
    }
}
