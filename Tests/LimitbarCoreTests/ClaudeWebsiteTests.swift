import XCTest
import WebKit
@testable import LimitbarCore

final class ClaudeWebsiteDecoderTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        return value
    }
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
    private func decode(_ cards: [[String: Any]], at now: Date) throws -> UsageSnapshot {
        try ClaudeWebsiteDecoder.decode(JSONSerialization.data(withJSONObject: cards), at: now, calendar: calendar)
    }

    func testScreenshotValuesAndLocalResetDates() throws {
        let result = try decode([
            ["id": "session", "text": "Current session\nResets at 6:30 PM\n7% used", "resetText": "Resets at 6:30 PM"],
            ["id": "weekly", "text": "This week\nResets Tuesday 11:00 PM\n18% used", "resetText": "Resets Tuesday 11:00 PM"]
        ], at: date("2026-10-22T19:30:00Z"))
        XCTAssertEqual(result.windows.map(\.name), ["Current session", "This week"])
        XCTAssertEqual(result.windows.map(\.usedPercent), [7, 18])
        XCTAssertEqual(result.windows.map(\.resetIsApproximate), [true, true])
        XCTAssertEqual(result.windows[0].resetsAt, date("2026-10-22T22:30:00Z"))
        XCTAssertEqual(result.windows[1].resetsAt, date("2026-10-28T03:00:00Z"))
    }

    func testSessionResetCrossesMidnightAndHandlesTwelveAM() throws {
        let result = try decode([["id": "session", "text": "7% used", "resetText": "Resets at 12:30 AM"]], at: date("2026-10-23T03:30:00Z"))
        XCTAssertEqual(result.windows[0].resetsAt, date("2026-10-23T04:30:00Z"))
    }

    func testWeeklyResetUsesCalendarAcrossDaylightSavingChange() throws {
        let result = try decode([["id": "weekly", "text": "18% used", "resetText": "Resets Tuesday 11:00 PM"]], at: date("2026-10-31T18:00:00Z"))
        XCTAssertEqual(result.windows[0].resetsAt, date("2026-11-04T04:00:00Z"))
    }

    func testInvalidOrAmbiguousResetClocksStayUnknown() throws {
        for text in ["Resets at 25:00 PM", "Resets at 6:99 PM", "Resets soon", "Resets at 6:30", "Resets at 6:30 PM UTC", "Resets Tuesday 11:00 PM"] {
            let result = try decode([["id": "session", "text": "7% used", "resetText": text]], at: date("2026-10-22T19:30:00Z"))
            XCTAssertNil(result.windows[0].resetsAt, text)
        }
        let weekly = try decode([["id": "weekly", "text": "18% used", "resetText": "Resets at 6:30 PM"]], at: date("2026-10-22T19:30:00Z"))
        XCTAssertNil(weekly.windows[0].resetsAt)
    }

    func testUsageValidationRejectsAmbiguousAndUnknownValues() {
        for text in ["7%", "7% used and 93% remaining", "-7% used", "107% used", "Unavailable"] {
            XCTAssertThrowsError(try decode([["id": "session", "text": text]], at: date("2026-10-22T19:30:00Z")))
        }
        XCTAssertThrowsError(try decode([["id": "review", "text": "7% used"]], at: date("2026-10-22T19:30:00Z")))
    }

    func testClaudeURLPolicyAndSourcePersistence() throws {
        XCTAssertTrue(ClaudeWebsiteDecoder.isUsageURL(ClaudeWebsiteDecoder.usageURL))
        XCTAssertTrue(ClaudeWebsiteDecoder.isUsageURL(URL(string: "https://claude.ai/settings/usage")!))
        for url in ["https://claude.ai/new", "https://claude.ai/new#settings/general", "https://claude.ai.evil.example/new#settings/usage", "http://claude.ai/new#settings/usage", "https://chatgpt.com/settings/usage"] {
            XCTAssertFalse(ClaudeWebsiteDecoder.isUsageURL(URL(string: url)!))
        }
        let plan = TrackedPlan(provider: .claude, name: "Claude website", source: .claudeWeb)
        XCTAssertEqual(try JSONDecoder().decode(TrackedPlan.self, from: JSONEncoder().encode(plan)), plan)
        XCTAssertEqual(plan.website, ClaudeWebsiteDecoder.usageURL)
    }
}

@MainActor
final class ClaudeWebsiteDOMTests: XCTestCase {
    private func extract(_ html: String, origin: String = "https://claude.ai", path: String = "/new", hash: String = "#settings/usage") async throws -> String {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        webView.loadHTMLString(html, baseURL: nil)
        let deadline = Date().addingTimeInterval(10)
        while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        let script = "(() => { const location = {origin: '\(origin)', pathname: '\(path)', hash: '\(hash)'}; return \(ClaudeWebsiteScript.extractionScript); })()"
        let result = try await webView.evaluateJavaScript(script)
        return try XCTUnwrap(result as? String)
    }

    func testScreenshotLabelsAndResetTextAreReadFromSeparateRows() async throws {
        let json = try await extract("""
        <main><h1>Your usage</h1><p>On track. You should reach Tuesday’s reset with room to spare.</p>
        <div><div><div>Current session</div><span>Resets at 6:30 PM</span></div><progress value="7" max="100"></progress><p>7% used</p></div>
        <div><div><div>This week</div><span>Resets Tuesday 11:00 PM</span></div><progress value="18" max="100"></progress><p>18% used</p></div>
        <h2>Limit resets</h2><p>No resets right now</p></main>
        """)
        let snapshot = try ClaudeWebsiteDecoder.decode(Data(json.utf8))
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [7, 18])
        let objects = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        XCTAssertEqual(objects[0]["resetText"] as? String, "Resets at 6:30 PM")
        XCTAssertEqual(objects[1]["resetText"] as? String, "Resets Tuesday 11:00 PM")
    }

    func testWrongHashAndOtherDomainsAreNotInspected() async throws {
        let html = "<div><h3>Current session</h3><p>7% used</p></div>"
        let wrongHash = try await extract(html, hash: "#settings/general")
        let wrongHost = try await extract(html, origin: "https://example.com")
        XCTAssertEqual(wrongHash, "[]")
        XCTAssertEqual(wrongHost, "[]")
        let legacy = try await extract(html, path: "/settings/usage", hash: "")
        XCTAssertEqual(try ClaudeWebsiteDecoder.decode(Data(legacy.utf8)).windows.first?.usedPercent, 7)
    }

    func testMissingSessionDoesNotBorrowTheWeeklyPercentage() async throws {
        let json = try await extract("<main><div><p>Current session</p><p>Unavailable</p></div><div><p>This week</p><p>18% used</p></div></main>")
        let result = try ClaudeWebsiteDecoder.decode(Data(json.utf8))
        XCTAssertEqual(result.windows.map(\.name), ["This week"])
    }
}
