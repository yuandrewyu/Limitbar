import Foundation

public struct PlanConfiguration: Codable {
    public var version: Int = 1
    public var plans: [TrackedPlan]
    public var codexExecutable: String
    /// Retain old entries for recovery without showing or editing manual subscriptions.
    public var archivedManualPlans: [TrackedPlan]?

    public init(plans: [TrackedPlan] = [], codexExecutable: String = "") {
        self.plans = plans
        self.codexExecutable = codexExecutable
    }

    @discardableResult
    public mutating func archiveManualPlans() -> Bool {
        let manual = plans.filter { $0.source == .manual }
        guard !manual.isEmpty else { return false }
        archivedManualPlans = (archivedManualPlans ?? []) + manual
        plans.removeAll { $0.source == .manual }
        return true
    }
}

public struct PlanRepository {
    public let fileURL: URL
    public init(fileURL: URL = LimitbarPaths.directory.appendingPathComponent("plans.json")) {
        self.fileURL = fileURL
    }

    public func load() throws -> PlanConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return PlanConfiguration() }
        let data = try Data(contentsOf: fileURL)
        let configuration = try JSONDecoder().decode(PlanConfiguration.self, from: data)
        guard configuration.version == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return configuration
    }

    public func save(_ configuration: PlanConfiguration) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
