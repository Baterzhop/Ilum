import Foundation

public enum ToolRisk: Int, Codable, Comparable, Sendable {
    case readOnly = 0
    case internalWrite = 1
    case userWrite = 2
    case externalAction = 3
    case system = 4
    case codeModification = 5

    public static func < (lhs: ToolRisk, rhs: ToolRisk) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum ToolCapability: String, Codable, Sendable, Hashable {
    case readAppData
    case writeAppData
    case readUserFile
    case writeUserFile
    case externalAction
    case systemCommand
    case modifyCode
}

public struct ResourceScope: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case appData, file, userFile, directory, externalService, system, codebase
    }
    public let kind: Kind
    public let identifier: String
    public init(kind: Kind, identifier: String) { self.kind = kind; self.identifier = identifier }
    public static func file(_ identifier: String) -> ResourceScope { .init(kind: .file, identifier: identifier) }
    public static func userFile(_ id: UserFileResourceID) -> ResourceScope { .init(kind: .userFile, identifier: id.rawValue) }
    public static func appData(_ identifier: String) -> ResourceScope { .init(kind: .appData, identifier: identifier) }
}

public enum GrantDuration: String, Codable, Sendable { case once, session }

public struct PermissionRequest: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let capability: ToolCapability
    public let resource: ResourceScope
    public let reason: String
    public let resourceDisplayName: String?
    public let resourceLocationHint: String?

    public init(
        id: UUID = UUID(),
        capability: ToolCapability,
        resource: ResourceScope,
        reason: String,
        resourceDisplayName: String? = nil,
        resourceLocationHint: String? = nil
    ) {
        self.id = id
        self.capability = capability
        self.resource = resource
        self.reason = reason
        self.resourceDisplayName = resourceDisplayName
        self.resourceLocationHint = resourceLocationHint
    }

    /// Session grants are deliberately limited to read-only capabilities.
    /// Writes, external actions, system commands and code changes must receive a
    /// fresh user decision for every concrete tool execution.
    public var allowsSessionGrant: Bool {
        switch capability {
        case .readAppData, .readUserFile:
            return true
        case .writeAppData, .writeUserFile, .externalAction, .systemCommand, .modifyCode:
            return false
        }
    }
}

public struct PermissionGrant: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let capability: ToolCapability
    public let resource: ResourceScope
    public let duration: GrantDuration
    /// A one-shot grant is bound to one concrete execution identity. Session
    /// read grants deliberately leave this nil and remain resource-scoped.
    public let executionID: UUID?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        capability: ToolCapability,
        resource: ResourceScope,
        duration: GrantDuration,
        executionID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.capability = capability
        self.resource = resource
        self.duration = duration
        self.executionID = executionID
        self.createdAt = createdAt
    }
}

public actor PermissionEngine {
    private var grants: [UUID: PermissionGrant] = [:]
    private let automaticallyAllowedCapabilities: Set<ToolCapability>

    public init(automaticallyAllowedCapabilities: Set<ToolCapability> = []) {
        self.automaticallyAllowedCapabilities = automaticallyAllowedCapabilities
    }

    /// Creates an authorization grant. For one-shot grants, `executionID` must
    /// identify the concrete ToolCall/execution being approved. Direct callers
    /// that do not supply one are safely bound to this PermissionRequest's ID.
    /// Session grants remain resource-scoped and are available only to read-only
    /// capabilities through `PermissionRequest.allowsSessionGrant`.
    @discardableResult
    public func grant(
        _ request: PermissionRequest,
        duration: GrantDuration,
        executionID: UUID? = nil
    ) -> PermissionGrant {
        let effectiveDuration: GrantDuration = request.allowsSessionGrant ? duration : .once
        let effectiveExecutionID = effectiveDuration == .once
            ? (executionID ?? request.id)
            : nil

        let duplicates = grants.values.filter { existing in
            guard existing.capability == request.capability,
                  existing.resource == request.resource else { return false }
            switch effectiveDuration {
            case .session:
                // A session read grant subsumes previous grants for this exact
                // capability/resource for the remainder of the session.
                return true
            case .once:
                // Distinct concrete executions on the same resource must be able
                // to coexist without replacing each other's approval.
                return existing.duration == .once &&
                    existing.executionID == effectiveExecutionID
            }
        }.map(\.id)
        for id in duplicates { grants.removeValue(forKey: id) }

        let grant = PermissionGrant(
            capability: request.capability,
            resource: request.resource,
            duration: effectiveDuration,
            executionID: effectiveExecutionID
        )
        grants[grant.id] = grant
        return grant
    }

    public func revoke(grantID: UUID) { grants.removeValue(forKey: grantID) }
    public func revokeAll() { grants.removeAll() }

    /// Authorizes one concrete execution. A session read grant can authorize any
    /// matching execution in the same session. A one-shot grant must match both
    /// capability/resource and the exact execution identity, so approval for one
    /// ToolCall cannot be consumed by a concurrent call on the same resource.
    public func authorize(
        _ request: PermissionRequest,
        executionID: UUID? = nil
    ) -> Bool {
        if automaticallyAllowedCapabilities.contains(request.capability) {
            return true
        }

        if grants.values.contains(where: {
            $0.duration == .session &&
            $0.capability == request.capability &&
            $0.resource == request.resource
        }) {
            return true
        }

        let requiredExecutionID = executionID ?? request.id
        guard let match = grants.values.first(where: {
            $0.duration == .once &&
            $0.capability == request.capability &&
            $0.resource == request.resource &&
            $0.executionID == requiredExecutionID
        }) else { return false }

        grants.removeValue(forKey: match.id)
        return true
    }

    public func activeGrants() -> [PermissionGrant] {
        grants.values.sorted { $0.createdAt < $1.createdAt }
    }
}
