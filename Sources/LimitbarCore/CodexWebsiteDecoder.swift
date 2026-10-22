import Foundation

/// Reads only labeled quota cards supplied by the website adapter, never a whole page or credentials.
public enum CodexWebsiteDecoder {
    public static let usageURL = URL(string: "https://chatgpt.com/settings/usage?tab=overview")!

    public static func isUsageURL(_ url: URL) -> Bool {
        let paths = ["/settings/usage", "/codex/settings/usage", "/codex/cloud/settings/usage", "/codex/cloud/settings/analytics"]
        return url.scheme == "https" && url.host == "chatgpt.com" &&
            paths.contains("/" + url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    public static func decode(_ data: Data, at now: Date = Date()) throws -> UsageSnapshot {
        struct Card: Decodable {
            let id: String
            let text: String
            let resetISO: String?
            let resetText: String?
        }
        let cards = try JSONDecoder().decode([Card].self, from: data)
        guard cards.count <= 3 else { throw WebsiteError.unrecognized }
        let names = ["session": "5 hours", "weekly": "Weekly", "review": "Code review"]
        var windows: [UsageWindow] = []
        var seen = Set<String>()
        for card in cards {
            guard let name = names[card.id], seen.insert(card.id).inserted,
                  card.text.count <= 1500 else { throw WebsiteError.unrecognized }
            // A naked percentage has no reliable direction. Reject multiple percentages as ambiguous.
            let text = card.text.replacingOccurrences(of: "\u{00a0}", with: " ")
            let range = NSRange(text.startIndex..., in: text)
            let all = try NSRegularExpression(pattern: #"[-+]?\d+(?:[.,]\d+)?\s*%"#)
            let percentages = all.matches(in: text, range: range)
            guard percentages.count == 1 else { continue }
            let labeled = try NSRegularExpression(pattern: #"(?i)(\d+(?:\.\d+)?)\s*%\s*(remaining|left|used)\b"#)
            guard let match = labeled.firstMatch(in: text, range: range),
                  match.range.location == percentages[0].range.location,
                  let valueRange = Range(match.range(at: 1), in: text),
                  let directionRange = Range(match.range(at: 2), in: text),
                  let value = Double(text[valueRange]), (0...100).contains(value),
                  let wholeRange = Range(match.range, in: text),
                  !text[..<wholeRange.lowerBound].hasSuffix("-") else { continue }
            let used = text[directionRange].lowercased() == "used" ? value : 100 - value
            var reset: Date?
            if let iso = card.resetISO {
                let formatter = ISO8601DateFormatter()
                reset = formatter.date(from: iso)
                if reset == nil {
                    formatter.formatOptions.insert(.withFractionalSeconds)
                    reset = formatter.date(from: iso)
                }
            }
            let estimatedReset = reset == nil ? relativeReset(in: card.resetText ?? text, at: now) : nil
            windows.append(UsageWindow(id: "website.\(card.id)", name: name, usedPercent: used,
                                       resetsAt: reset ?? estimatedReset,
                                       resetIsApproximate: estimatedReset == nil ? nil : true))
        }
        guard !windows.isEmpty else { throw WebsiteError.unrecognized }
        return UsageSnapshot(capturedAt: now, windows: windows)
    }

    private static func relativeReset(in text: String, at now: Date) -> Date? {
        // Only an explicit duration is usable. A clock time alone has no date/time zone.
        let expression = try! NSRegularExpression(pattern: #"(?im)^\s*resets\s+in\s+((?:\d+\s*[dhms]\s*)+)\s*$"#)
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count == 1, let range = Range(matches[0].range(at: 1), in: text) else { return nil }
        let duration = String(text[range])
        let tokens = try! NSRegularExpression(pattern: #"(?i)(\d+)\s*([dhms])"#)
        let units: [String: Double] = ["d": 86400, "h": 3600, "m": 60, "s": 1]
        var seconds: Double = 0
        var seen = Set<String>()
        for token in tokens.matches(in: duration, range: NSRange(duration.startIndex..., in: duration)) {
            guard let amountRange = Range(token.range(at: 1), in: duration),
                  let unitRange = Range(token.range(at: 2), in: duration),
                  let amount = Double(duration[amountRange]) else { return nil }
            let unit = duration[unitRange].lowercased()
            guard seen.insert(unit).inserted, let multiplier = units[unit] else { return nil }
            seconds += amount * multiplier
        }
        guard !seen.isEmpty, seconds.isFinite, (0...8 * 86400).contains(seconds) else { return nil }
        return now.addingTimeInterval(seconds)
    }

    public enum WebsiteError: LocalizedError {
        case unrecognized
        public var errorDescription: String? {
            "No clearly labeled Codex usage was found. Sign in, open the English Codex usage page, and try again. The website layout may be unsupported."
        }
    }
}
