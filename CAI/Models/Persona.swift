import Foundation

/// The user's SAP specialty, sent as chat context so responses use the right
/// terminology and depth (bluefunda/cai-ios#177). Additive to the existing
/// `agentName`-based routing (e.g. "abaper") rather than a replacement for
/// it — there's no BASIS/FI/IS-U/Leader agent on the backend yet, so this is
/// a separate, backend-optional field the router can pick up when ready.
enum Persona: String, CaseIterable, Identifiable, Codable {
    case general
    case abap
    case basis
    case fi
    case isU = "is-u"
    case leader

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        case .abap:    return "ABAP Developer"
        case .basis:   return "BASIS Admin"
        case .fi:      return "FI / FI-CA Consultant"
        case .isU:     return "IS-U Consultant"
        case .leader:  return "Leader / SI Founder"
        }
    }

    var detail: String {
        switch self {
        case .general: return "No specific SAP focus"
        case .abap:    return "Custom development, dumps, and code review"
        case .basis:   return "System administration and technical operations"
        case .fi:      return "Financial Accounting and Contract Accounting"
        case .isU:     return "Utilities industry solution"
        case .leader:  return "Engagement scoping and client delivery"
        }
    }

    var icon: String {
        switch self {
        case .general: return "sparkles"
        case .abap:    return "chevron.left.forwardslash.chevron.right"
        case .basis:   return "server.rack"
        case .fi:      return "dollarsign.circle"
        case .isU:     return "bolt.fill"
        case .leader:  return "briefcase"
        }
    }
}
