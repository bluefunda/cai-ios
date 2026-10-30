import SwiftUI

// MARK: - Status Pill Style
// The one place a change-request status turns into colour (docs/BLUEREQUESTS_INTEGRATION.md
// P13). The wire only sends blocked/planned/inprogress/completed today (see
// ChangeRequestStatus); the design's wider vocabulary (draft, submitted, in review,
// approved, rejected, deployed/transported, closed/archived) is matched from `.other`
// so a backend that starts sending those gets the right colour without a client change.

struct RQStatusStyle: Equatable {
    enum Family: Equatable {
        case neutral, blue, orange, green, red, purple
        /// Closed / archived: neutral, at 60% opacity.
        case muted
    }

    let family: Family
    /// Sentence case, per P13 copy rules ("In progress", not "In Progress").
    let label: String

    var fill: Color {
        switch family {
        case .neutral: return BFColor.statusNeutralFill
        case .muted: return BFColor.statusNeutralFill.opacity(0.6)
        case .blue: return BFColor.statusBlueFill
        case .orange: return BFColor.statusOrangeFill
        case .green: return BFColor.statusGreenFill
        case .red: return BFColor.statusRedFill
        case .purple: return BFColor.statusPurpleFill
        }
    }

    /// The saturated mark for the stage rail's current segment and timeline dots — a
    /// pill's tint fill is too pale to read as a 4 pt bar on the light canvas.
    var mark: Color {
        switch family {
        case .neutral, .muted: return BFColor.neutral400
        case .blue: return BFColor.secondaryAdaptive
        case .orange: return BFColor.happyOrange
        case .green: return BFColor.success
        case .red: return BFColor.happyRed
        case .purple: return BFColor.happyPurple
        }
    }

    var text: Color {
        switch family {
        case .neutral: return BFColor.statusNeutralText
        case .muted: return BFColor.statusNeutralText.opacity(0.6)
        case .blue: return BFColor.statusBlueText
        case .orange: return BFColor.statusOrangeText
        case .green: return BFColor.statusGreenText
        case .red: return BFColor.statusRedText
        case .purple: return BFColor.statusPurpleText
        }
    }
}

extension ChangeRequestStatus {
    var style: RQStatusStyle {
        switch self {
        case .blocked: return RQStatusStyle(family: .red, label: "Blocked")
        case .planned: return RQStatusStyle(family: .blue, label: "Planned")
        case .inProgress: return RQStatusStyle(family: .orange, label: "In progress")
        case .completed: return RQStatusStyle(family: .green, label: "Completed")
        case .other(let raw): return Self.style(forOther: raw)
        }
    }

    private static func style(forOther raw: String) -> RQStatusStyle {
        let normalized = raw.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "draft": return RQStatusStyle(family: .neutral, label: "Draft")
        case "submitted": return RQStatusStyle(family: .blue, label: "Submitted")
        case "inreview", "review": return RQStatusStyle(family: .orange, label: "In review")
        case "approved": return RQStatusStyle(family: .green, label: "Approved")
        case "rejected": return RQStatusStyle(family: .red, label: "Rejected")
        case "deployed": return RQStatusStyle(family: .purple, label: "Deployed")
        case "transported": return RQStatusStyle(family: .purple, label: "Transported")
        case "closed": return RQStatusStyle(family: .muted, label: "Closed")
        case "archived": return RQStatusStyle(family: .muted, label: "Archived")
        default: return RQStatusStyle(family: .neutral, label: sentenceCase(raw))
        }
    }

    /// "in_review" → "In review", "" → "Unknown".
    private static func sentenceCase(_ raw: String) -> String {
        let words = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.lowercased() }
            .joined(separator: " ")
        guard let first = words.first else { return "Unknown" }
        return first.uppercased() + words.dropFirst()
    }
}
