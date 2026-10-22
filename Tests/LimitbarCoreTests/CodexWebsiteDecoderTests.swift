import Foundation
import XCTest
@testable import LimitbarCore

final class CodexWebsiteDecoderTests: XCTestCase {
    private func decode(_ cards: [[String: Any]]) throws -> UsageSnapshot {
        try CodexWebsiteDecoder.decode(JSONSerialization.data(withJSONObject: cards))
    }

    func testRemainingIsConvertedToUsedAndExactResetIsPreserved() throws {
        let result = try decode([
            ["id": "session", "text": "5 hour usage limit\n80% remaining", "resetISO": "2026-10-22T20:00:00Z"],
            ["id": "weekly", "text": "Weekly usage limit\n35% used", "resetISO": NSNull()]
        ])
        XCTAssertEqual(result.windows.map(\.usedPercent), [20, 35])
        XCTAssertEqual(result.windows[0].resetsAt, ISO8601DateFormatter().date(from: "2026-10-22T20:00:00Z"))
        XCTAssertNil(result.windows[1].resetsAt)
    }

    func testZeroAndFullUsageAreValidReadings() throws {
        let result = try decode([
            ["id": "session", "text": "100% left"],
            ["id": "weekly", "text": "0% remaining"]
        ])
        XCTAssertEqual(result.windows.map(\.usedPercent), [0, 100])
    }

    func testUnlabeledAndAmbiguousPercentagesAreNotImported() {
        for text in ["80%", "80% remaining, 20% used", "Upgrade for 50% off", "-5% used", "101% remaining", "1,5% used"] {
            XCTAssertThrowsError(try decode([["id": "session", "text": text]]), text)
        }
    }

    func testUnknownWindowDoesNotBecomeZeroAndPartialReadingsRemainPartial() throws {
        let result = try decode([
            ["id": "session", "text": "Usage unavailable"],
            ["id": "weekly", "text": "90% remaining"]
        ])
        XCTAssertEqual(result.windows.count, 1)
        XCTAssertEqual(result.windows[0].id, "website.weekly")
        XCTAssertEqual(result.windows[0].usedPercent, 10)
        XCTAssertThrowsError(try decode([]))
    }

    func testClockTextWithoutTimestampIsNotGuessed() throws {
        let result = try decode([["id": "session", "text": "60% remaining\nResets at 4:00 PM", "resetISO": "4:00 PM"]])
        XCTAssertNil(result.windows[0].resetsAt)
    }

    func testUnifiedAndLegacyUsageURLsAreAcceptedButOtherOriginsAreRejected() {
        for path in ["/settings/usage", "/settings/usage/", "/codex/settings/usage", "/codex/cloud/settings/usage", "/codex/cloud/settings/analytics"] {
            XCTAssertTrue(CodexWebsiteDecoder.isUsageURL(URL(string: "https://chatgpt.com\(path)")!))
        }
        for url in ["http://chatgpt.com/settings/usage", "https://chatgpt.com.evil.example/settings/usage", "https://chatgpt.com/auth/login", "https://chatgpt.com/settings/usage/other"] {
            XCTAssertFalse(CodexWebsiteDecoder.isUsageURL(URL(string: url)!))
        }
    }

    func testMalformedAndAmbiguousResetDurationsStayUnknown() throws {
        for text in ["Resets in -3h", "Resets in 3h 3h", "Resets in 999d", "Resets in 2h tomorrow", "Resets in 2h\nResets in 3h"] {
            let result = try decode([["id": "session", "text": "73% left\n\(text)"]])
            XCTAssertNil(result.windows[0].resetsAt, text)
            XCTAssertNil(result.windows[0].resetIsApproximate, text)
        }
    }

    func testOlderSavedWindowWithoutApproximateFlagStillLoads() throws {
        let data = Data(#"{"id":"old","name":"Weekly","usedPercent":25}"#.utf8)
        let window = try JSONDecoder().decode(UsageWindow.self, from: data)
        XCTAssertEqual(window.usedPercent, 25)
        XCTAssertNil(window.resetIsApproximate)
    }

    func testDuplicateAndUnexpectedCardsAreRejected() {
        XCTAssertThrowsError(try decode([
            ["id": "session", "text": "80% remaining"],
            ["id": "session", "text": "10% remaining"]
        ]))
        XCTAssertThrowsError(try decode([["id": "advertisement", "text": "50% used"]]))
    }

    func testWebsiteSourceCanBeSavedWithoutChangingExistingPlans() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = PlanRepository(fileURL: directory.appendingPathComponent("plans.json"))
        let manual = TrackedPlan(provider: .claude, name: "My plan")
        let web = TrackedPlan(provider: .chatgpt, name: "Codex", source: .codexWeb,
                              snapshot: try decode([["id": "session", "text": "80% remaining"]]))
        try repository.save(PlanConfiguration(plans: [manual, web]))
        let restored = try repository.load()
        XCTAssertEqual(restored.plans, [manual, web])
        XCTAssertEqual(web.website.absoluteString, "https://chatgpt.com/settings/usage?tab=overview")
    }
}
