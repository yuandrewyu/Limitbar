import Foundation
import LimitbarCore

// Website readers share the window and refresh lifecycle, while keeping their own sessions and adapters.
enum WebsiteService {
    case codex, claude

    var name: String { self == .codex ? "Codex" : "Claude" }
    var source: UsageSource { self == .codex ? .codexWeb : .claudeWeb }
    var provider: Provider { self == .codex ? .chatgpt : .claude }
    var usageURL: URL { self == .codex ? CodexWebsiteDecoder.usageURL : ClaudeWebsiteDecoder.usageURL }
    var extractionScript: String {
        self == .codex ? CodexWebsiteScript.extractionScript : ClaudeWebsiteScript.extractionScript
    }
    func isUsageURL(_ url: URL) -> Bool {
        self == .codex ? CodexWebsiteDecoder.isUsageURL(url) : ClaudeWebsiteDecoder.isUsageURL(url)
    }
    func decode(_ data: Data) throws -> UsageSnapshot {
        try self == .codex ? CodexWebsiteDecoder.decode(data) : ClaudeWebsiteDecoder.decode(data)
    }
}
