import Foundation

public enum UsageDecodingError: LocalizedError {
    case invalidPercentage
    case noRateLimits
    public var errorDescription: String? {
        switch self {
        case .invalidPercentage: return "The provider returned an invalid usage percentage."
        case .noRateLimits: return "No subscription limits were returned. Check the CLI login and plan."
        }
    }
}

public enum UsageDecoders {
    /// Only the documented rate-limit fields are decoded; prompts and transcripts are ignored.
    public static func claudeStatusLine(_ data: Data, at now: Date = Date()) throws -> UsageSnapshot {
        struct Window: Decodable { let used_percentage: Double?; let resets_at: Double? }
        struct Limits: Decodable { let five_hour: Window?; let seven_day: Window? }
        struct Input: Decodable { let rate_limits: Limits? }
        let input = try JSONDecoder().decode(Input.self, from: data)
        var windows: [UsageWindow] = []
        for (id, name, window) in [
            ("five_hour", "5 hours", input.rate_limits?.five_hour),
            ("seven_day", "7 days", input.rate_limits?.seven_day)
        ] {
            guard let window else { continue }
            try validate(window.used_percentage)
            windows.append(UsageWindow(id: id, name: name, usedPercent: window.used_percentage,
                                       resetsAt: window.resets_at.map(Date.init(timeIntervalSince1970:))))
        }
        return UsageSnapshot(capturedAt: now, windows: windows)
    }

    /// Decodes the result object from account/rateLimits/read, including all returned buckets.
    public static func codexRateLimits(_ data: Data, at now: Date = Date()) throws -> UsageSnapshot {
        struct Window: Decodable {
            let usedPercent: Double?
            let windowDurationMins: Int?
            let resetsAt: Double?
        }
        struct Bucket: Decodable {
            let limitId: String?
            let limitName: String?
            let primary: Window?
            let secondary: Window?
        }
        struct Result: Decodable {
            let rateLimits: Bucket?
            let rateLimitsByLimitId: [String: Bucket]?
        }
        let result = try JSONDecoder().decode(Result.self, from: data)
        let buckets: [(String, Bucket)]
        if let all = result.rateLimitsByLimitId, !all.isEmpty {
            buckets = all.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        } else if let single = result.rateLimits {
            buckets = [(single.limitId ?? "codex", single)]
        } else {
            throw UsageDecodingError.noRateLimits
        }
        var windows: [UsageWindow] = []
        for (id, bucket) in buckets {
            for (slot, window) in [("primary", bucket.primary), ("secondary", bucket.secondary)] {
                guard let window else { continue }
                try validate(window.usedPercent)
                let duration = durationName(minutes: window.windowDurationMins, fallback: slot.capitalized)
                let name = buckets.count > 1 ? "\(bucket.limitName ?? id) · \(duration)" : duration
                windows.append(UsageWindow(id: "\(id).\(slot)", name: name,
                                           usedPercent: window.usedPercent,
                                           resetsAt: window.resetsAt.map(Date.init(timeIntervalSince1970:))))
            }
        }
        guard !windows.isEmpty else { throw UsageDecodingError.noRateLimits }
        return UsageSnapshot(capturedAt: now, windows: windows)
    }

    private static func validate(_ percent: Double?) throws {
        if let percent, !percent.isFinite || percent < 0 { throw UsageDecodingError.invalidPercentage }
    }

    private static func durationName(minutes: Int?, fallback: String) -> String {
        guard let minutes, minutes > 0 else { return fallback }
        if minutes % 1440 == 0 {
            let days = minutes / 1440
            return "\(days) \(days == 1 ? "day" : "days")"
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return "\(hours) \(hours == 1 ? "hour" : "hours")"
        }
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }
}
