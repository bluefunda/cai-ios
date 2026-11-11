import Foundation

// MARK: - Stage Flow
// The web's stage buttons (changeRequestDetail.js) and push drawer (commonStagingFlow):
// first stage → Start; the stage before the last → Revert / Mark this as completed; any
// other stage before that → Revert / Push to next stage; the last stage has none (Archive
// lives in the menu). None of them show when the tenant enforces the approval workflow —
// steps then move by Approve/Reject instead.

enum StageMoveKind: Equatable {
    case start, next, complete, revert

    var title: String {
        switch self {
        case .start: return "Start"
        case .next: return "Push to next stage"
        case .complete: return "Mark as completed"
        case .revert: return "Push to previous stage"
        }
    }
}

struct StageMove: Equatable {
    let kind: StageMoveKind
    let from: RQStage
    let to: RQStage
    /// The request's status once it's at `to`, as the web sets it after a move: planned at
    /// the first stage, completed at the last, in progress in between.
    let status: ChangeRequestStatus
    /// Deploy to QA on an SAP or Git request runs transport releases or a branch merge,
    /// and marking an SAP request complete releases its transports, before the stage moves.
    /// The app doesn't drive those yet, so such a move is left to the web.
    let needsWeb: Bool
}

struct StageActions: Equatable {
    var forward: StageMove?
    var revert: StageMove?

    static let none = StageActions()
}

extension ChangeRequest {
    var usesSAP: Bool { platforms.contains(where: \.isSAP) }
    var usesGit: Bool { platforms.contains(where: \.usesGit) }

    func stageActions(workflowEnforced: Bool) -> StageActions {
        guard !workflowEnforced, let current = currentStage, let last = stages.last,
              current.order < last.order else { return .none }

        func move(_ kind: StageMoveKind, to order: Int) -> StageMove? {
            guard let target = stages.first(where: { $0.order == order }) else { return nil }
            let status: ChangeRequestStatus = order == 1 ? .planned
                : order == stages.count ? .completed : .inProgress
            let forward = kind != .revert
            let deploysToQA = forward && current.qaDeploy && (usesSAP || usesGit)
            let releasesTransports = kind == .complete && usesSAP
            return StageMove(kind: kind, from: current, to: target, status: status,
                             needsWeb: deploysToQA || releasesTransports)
        }

        var actions = StageActions()
        let nextOrder = current.order + 1
        let kind: StageMoveKind = current.order == 1 ? .start
            : nextOrder == last.order ? .complete : .next
        actions.forward = move(kind, to: nextOrder)
        if current.order > 1 {
            actions.revert = move(.revert, to: current.order - 1)
        }
        return actions
    }
}

extension ChangeRequest {
    /// The stage a board drop into `status`'s column moves the request to, as the web's
    /// Grid view (changeRequestHome.js updatestatus) does: planned is the first stage, in
    /// progress the second, completed the last. Other columns, or a drop that lands on the
    /// stage the request is already at, move no stage.
    func boardStageTarget(for status: ChangeRequestStatus) -> RQStage? {
        let target: RQStage?
        switch status {
        case .planned: target = stages.first
        case .inProgress: target = stages.count > 1 ? stages[1] : nil
        case .completed: target = stages.last
        default: target = nil
        }
        guard let target, target.order != currentStage?.order else { return nil }
        return target
    }
}

/// PUT /rest/trm/v1/stage — the target stage, as the web's stageUpdateFunc sends it. The
/// owner goes with it because the backend writes it onto the stage it moves to.
struct StageUpdatePayload: Encodable, Equatable {
    let order: Int
    let owner: String?
    let updatedBy: String
    let changeRequestId: Int
    let current: Bool
    let statusCode: String
    let description: String

    init(move: StageMove, changeRequestId: Int, updatedBy: String, totalStages: Int) {
        order = move.to.order
        owner = move.to.ownerId
        self.updatedBy = updatedBy
        self.changeRequestId = changeRequestId
        current = move.to.order == totalStages
        statusCode = move.to.statusCode
        description = move.to.description
    }

    /// A board drop's stage move. The web sends `current: true` from the board.
    init(stage: RQStage, changeRequestId: Int, updatedBy: String) {
        order = stage.order
        owner = stage.ownerId
        self.updatedBy = updatedBy
        self.changeRequestId = changeRequestId
        current = true
        statusCode = stage.statusCode
        description = stage.description
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(order, forKey: .order)
        try c.encode(owner, forKey: .owner)  // null clears nothing: it's the target's own owner
        try c.encode(updatedBy, forKey: .updatedBy)
        try c.encode(changeRequestId, forKey: .changeRequestId)
        try c.encode(current, forKey: .current)
        try c.encode(statusCode, forKey: .statusCode)
        try c.encode(description, forKey: .description)
    }

    private enum CodingKeys: String, CodingKey {
        case order, owner, updatedBy, changeRequestId, current, statusCode, description
    }
}

/// The stage endpoint answers 200 even when it fails, with `status: "error"`.
struct StageUpdateResponse: Decodable {
    let status: String?
    let message: String?
}

// MARK: - Approval Workflow
// GET /change-requests/{id}/workflow (trm-backend-go internal/workflow View). Only an
// `enforced` view changes anything on screen: steps with Approve/Reject replace the stage
// buttons.

struct RQWorkflow: Decodable, Equatable {
    let enforced: Bool
    let currentOrder: Int?
    let steps: [RQWorkflowStep]

    private enum CodingKeys: String, CodingKey { case enforced, currentOrder, steps }

    init(enforced: Bool, currentOrder: Int? = nil, steps: [RQWorkflowStep]) {
        self.enforced = enforced
        self.currentOrder = currentOrder
        self.steps = steps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enforced = (try? c.decodeIfPresent(Bool.self, forKey: .enforced)) ?? false
        currentOrder = (try? c.decodeIfPresent(Int.self, forKey: .currentOrder)) ?? nil
        steps = (try? c.decodeIfPresent([RQWorkflowStep].self, forKey: .steps)) ?? []
    }
}

struct RQWorkflowStep: Decodable, Equatable, Identifiable {
    struct Gate: Decodable, Equatable {
        let status: String?
        let prs: Int?
    }

    let order: Int
    let statusCode: String
    let description: String
    let type: String
    let department: String
    let role: String
    let state: String
    let decisions: [RQWorkflowDecision]
    let gate: Gate?
    /// The stage owner's user id, when one was picked.
    let owner: String?
    /// Whether the signed-in user may decide this step (its owner, or its role and
    /// department), as the server says. nil from a server that doesn't say: then the
    /// buttons show and a refusal comes back as not_an_approver.
    let callerCanDecide: Bool?

    var id: Int { order }
    var title: String { description.isEmpty ? statusCode : description }
    var isGate: Bool { type == "github_gate" }
    /// The current approval step (the web's canDecideStep).
    var isAwaitingDecision: Bool { state == "current" && !isGate }
    /// Approve/Reject show only to someone who may decide.
    var canDecide: Bool { isAwaitingDecision && callerCanDecide != false }

    var stateLabel: String {
        switch state {
        case "pending": return "Pending"
        case "current": return "Current"
        case "approved": return "Approved"
        case "rejected": return "Rejected"
        case "satisfied": return "Satisfied"
        case "blocked": return "Blocked"
        default: return state.capitalized
        }
    }

    /// The web's GATE_STATUS_LABELS.
    var gateLabel: String? {
        guard let status = gate?.status else { return nil }
        switch status {
        case "none": return "No pull requests"
        case "pending": return "Pending review"
        case "changes_requested": return "Changes requested"
        case "approved": return "Approved"
        case "approved_stale": return "Approval is stale"
        case "merged": return "Merged"
        default: return status
        }
    }

    private enum CodingKeys: String, CodingKey {
        case order, statusCode, description, type, department, role, state, decisions, gate, owner
        case callerCanDecide = "canDecide"
    }

    init(order: Int, description: String, state: String, type: String = "approval",
         statusCode: String = "", department: String = "", role: String = "",
         decisions: [RQWorkflowDecision] = [], gate: Gate? = nil,
         owner: String? = nil, callerCanDecide: Bool? = nil) {
        self.owner = owner
        self.callerCanDecide = callerCanDecide
        self.order = order
        self.statusCode = statusCode
        self.description = description
        self.type = type
        self.department = department
        self.role = role
        self.state = state
        self.decisions = decisions
        self.gate = gate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = (try? c.decode(Int.self, forKey: .order)) ?? 0
        statusCode = (try? c.decodeIfPresent(String.self, forKey: .statusCode)) ?? ""
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
        type = ((try? c.decodeIfPresent(String.self, forKey: .type)) ?? nil).flatMap { $0.isEmpty ? nil : $0 } ?? "approval"
        department = (try? c.decodeIfPresent(String.self, forKey: .department)) ?? ""
        role = (try? c.decodeIfPresent(String.self, forKey: .role)) ?? ""
        state = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? ""
        decisions = (try? c.decodeIfPresent([RQWorkflowDecision].self, forKey: .decisions)) ?? []
        gate = (try? c.decodeIfPresent(Gate.self, forKey: .gate)) ?? nil
        owner = ((try? c.decodeIfPresent(String.self, forKey: .owner)) ?? nil).flatMap { $0.isEmpty ? nil : $0 }
        callerCanDecide = (try? c.decodeIfPresent(Bool.self, forKey: .callerCanDecide)) ?? nil
    }
}

struct RQWorkflowDecision: Decodable, Equatable, Identifiable {
    struct Actor: Decodable, Equatable {
        let sub: String?
        let name: String?
    }

    let id: String
    let decision: String
    let actor: Actor?
    let comment: String?
    let createdAt: Date?

    var isRejection: Bool { decision == WorkflowDecision.reject.rawValue }
    var actorName: String { actor?.name ?? actor?.sub ?? "Someone" }
}

enum WorkflowDecision: String, Encodable {
    case approve, reject
}

/// POST /change-requests/{id}/steps/{order}/decisions — the actor comes from the token.
struct WorkflowDecisionPayload: Encodable, Equatable {
    let decision: WorkflowDecision
    let comment: String
}

/// The web's DECISION_ERROR_MESSAGES, keyed by the server's error code.
enum WorkflowDecisionError {
    /// Codes after which the step has moved on or the setting changed: reload the workflow.
    static let refreshCodes: Set<String> = ["not_current_step", "step_is_gate", "workflow_not_enforced"]

    static func message(for error: Error) -> String {
        switch error {
        case RequestsAPIError.rejected(let status, let code, _):
            switch code {
            case "not_an_approver": return "You are not an approver for this step."
            case "not_current_step": return "This step is no longer the current step. The workflow has been refreshed."
            case "step_is_gate": return "This is a GitHub gate step. It completes automatically and can't be approved by hand."
            case "workflow_not_enforced": return "Workflow enforcement is turned off for your organization."
            default:
                // A coded 403 (see RequestsAPIClient.validateStatus) reads like a bare one.
                if status == 403 { return "You are not an approver for this step." }
            }
        case RequestsAPIError.requestsUnavailable(statusCode: 403):
            return "You are not an approver for this step."
        default: break
        }
        return "Could not record your decision. Please try again."
    }

    static func needsRefresh(_ error: Error) -> Bool {
        if case RequestsAPIError.rejected(_, let code, _) = error { return refreshCodes.contains(code) }
        return false
    }
}
