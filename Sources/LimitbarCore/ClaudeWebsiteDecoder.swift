import Foundation

public enum ClaudeWebsiteDecoder {
    public static let usageURL = URL(string: "https://claude.ai/new#settings/usage")!

    public static func isUsageURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host == "claude.ai" else { return false }
        let path = "/" + url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path == "/settings/usage" ||
            (path == "/new" && url.fragment?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "settings/usage")
    }

    public static func decode(_ data: Data, at now: Date = Date(), calendar: Calendar = .current) throws -> UsageSnapshot {
        struct Card: Decodable {
            let id: String
            let resetText: String?
        }
        let cards = try JSONDecoder().decode([Card].self, from: data)
        guard cards.count <= 2, cards.allSatisfy({ ["session", "weekly"].contains($0.id) }) else {
            throw WebsiteError.unrecognized
        }
        // Share strict percentage validation and explicit-duration handling with the Codex adapter.
        var snapshot: UsageSnapshot
        do { snapshot = try CodexWebsiteDecoder.decode(data, at: now) }
        catch { throw WebsiteError.unrecognized }
        for index in snapshot.windows.indices {
            let id = snapshot.windows[index].id.replacingOccurrences(of: "website.", with: "")
            snapshot.windows[index].name = id == "session" ? "Current session" : "This week"
            snapshot.windows[index].id = "claudeWebsite.\(id)"
            if snapshot.windows[index].resetsAt == nil,
               let text = cards.first(where: { $0.id == id })?.resetText,
               let reset = localReset(text, window: id, now: now, calendar: calendar) {
                snapshot.windows[index].resetsAt = reset
                snapshot.windows[index].resetIsApproximate = true
            }
        }
        return snapshot
    }

    private static func localReset(_ text: String, window: String, now: Date, calendar: Calendar) -> Date? {
        // The website displays these clocks in the browser's local time zone. Limitbar's embedded
        // browser and Calendar.current use the same Mac time zone. The missing date is inferred.
        let normalized = text.replacingOccurrences(of: "\u{202f}", with: " ").replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        let pattern = #"(?i)^resets\s+(?:(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\s+)?(?:at\s+)?(\d{1,2}):(\d{2})\s*(AM|PM)$"#
        let regex = try! NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) else { return nil }
        func group(_ number: Int) -> String? {
            Range(match.range(at: number), in: normalized).map { String(normalized[$0]) }
        }
        guard let hourText = group(2), let hour = Int(hourText), (1...12).contains(hour),
              let minuteText = group(3), let minute = Int(minuteText), (0...59).contains(minute),
              let meridiem = group(4) else { return nil }
        var components = DateComponents()
        components.hour = hour % 12 + (meridiem.lowercased() == "pm" ? 12 : 0)
        components.minute = minute
        components.second = 0
        if let day = group(1)?.lowercased(), let index = weekdays.firstIndex(of: day) {
            guard window == "weekly" else { return nil }
            components.weekday = index + 1
        } else if window == "weekly" { return nil }
        guard let date = calendar.nextDate(after: now.addingTimeInterval(-60), matching: components,
                                            matchingPolicy: .nextTime, repeatedTimePolicy: .first),
              date.timeIntervalSince(now) <= (window == "session" ? 5 * 3600 + 60 : 7 * 86400 + 3600) else { return nil }
        return date
    }

    public enum WebsiteError: LocalizedError {
        case unrecognized
        public var errorDescription: String? {
            "No clearly labeled Claude usage was found. Open Your usage in the English Claude settings and try again."
        }
    }
}
