import Foundation

public enum Provider: String, Codable, CaseIterable, Identifiable {
    case claude, chatgpt, gemini, other

    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        case .other: return "Other"
        }
    }

    public var website: URL {
        let address: String
        switch self {
        case .claude: address = "https://claude.ai/settings/usage"
        case .chatgpt: address = "https://chatgpt.com"
        case .gemini: address = "https://gemini.google.com"
        case .other: address = "https://example.com"
        }
        return URL(string: address)!
    }
}

public enum UsageSource: String, Codable, CaseIterable, Identifiable {
    case manual, claudeCode, codex
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .manual: return "Manual entry"
        case .claudeCode: return "Claude Code status line"
        case .codex: return "Codex CLI"
        }
    }
}

public struct UsageWindow: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    /// nil means unavailable. It must never be displayed as zero usage.
    public var usedPercent: Double?
    public var resetsAt: Date?

    public init(id: String = UUID().uuidString, name: String,
                usedPercent: Double? = nil, resetsAt: Date? = nil) {
        self.id = id
        self.name = name
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    public var fraction: Double? {
        guard let value = usedPercent, value.isFinite, value >= 0 else { return nil }
        return min(value / 100, 1)
    }

    public func hasReset(at now: Date) -> Bool {
        resetsAt.map { $0 <= now } ?? false
    }
}

public struct UsageSnapshot: Codable, Equatable {
    public var capturedAt: Date
    public var windows: [UsageWindow]

    public init(capturedAt: Date = Date(), windows: [UsageWindow]) {
        self.capturedAt = capturedAt
        self.windows = windows
    }

    public func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(capturedAt) > 15 * 60 || capturedAt > now.addingTimeInterval(60)
    }
}

public struct TrackedPlan: Codable, Identifiable, Equatable {
    public var id: UUID
    public var provider: Provider
    public var name: String
    public var source: UsageSource
    public var snapshot: UsageSnapshot?

    public init(id: UUID = UUID(), provider: Provider = .claude, name: String = "",
                source: UsageSource = .manual, snapshot: UsageSnapshot? = nil) {
        self.id = id
        self.provider = provider
        self.name = name
        self.source = source
        self.snapshot = snapshot
    }

    public var displayName: String { name.isEmpty ? provider.name : name }

    public var website: URL {
        source == .codex ? URL(string: "https://chatgpt.com/codex/settings/usage")! : provider.website
    }

    public func highestCurrentUsage(at now: Date) -> Double? {
        guard let snapshot, !snapshot.isStale(at: now) else { return nil }
        return snapshot.windows.filter { !$0.hasReset(at: now) }
            .compactMap(\.fraction).max()
    }
}

public enum LimitbarPaths {
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Limitbar", isDirectory: true)
    }
    public static var claudeSnapshot: URL { directory.appendingPathComponent("claude-usage.json") }
}
