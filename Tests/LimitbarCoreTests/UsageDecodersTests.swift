import Foundation
import XCTest
@testable import LimitbarCore

final class UsageDecodersTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testClaudeReadsOnlySubscriptionLimits() throws {
        let input = Data(#"{"context_window":{"used_percentage":99},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1800003600},"seven_day":{"used_percentage":41,"resets_at":1800604800}}}"#.utf8)
        let result = try UsageDecoders.claudeStatusLine(input, at: now)
        XCTAssertEqual(result.capturedAt, now)
        XCTAssertEqual(result.windows.map(\.usedPercent), [23.5, 41])
        XCTAssertEqual(result.windows.first?.resetsAt, now.addingTimeInterval(3600))
    }

    func testClaudeContextUsageIsNeverMistakenForPlanUsage() throws {
        let result = try UsageDecoders.claudeStatusLine(Data(#"{"context_window":{"used_percentage":80}}"#.utf8))
        XCTAssertTrue(result.windows.isEmpty)
    }

    func testClaudeAllowsIndependentlyMissingWindows() throws {
        let result = try UsageDecoders.claudeStatusLine(Data(#"{"rate_limits":{"seven_day":{"used_percentage":0}}}"#.utf8))
        XCTAssertEqual(result.windows.count, 1)
        XCTAssertEqual(result.windows[0].usedPercent, 0)
        XCTAssertNil(result.windows[0].resetsAt)
    }

    func testNullPercentageStaysUnknown() throws {
        let result = try UsageDecoders.claudeStatusLine(Data(#"{"rate_limits":{"five_hour":{"used_percentage":null}}}"#.utf8))
        XCTAssertNil(result.windows[0].usedPercent)
        XCTAssertNil(result.windows[0].fraction)
    }

    func testNegativeUsageIsRejected() {
        XCTAssertThrowsError(try UsageDecoders.claudeStatusLine(Data(#"{"rate_limits":{"five_hour":{"used_percentage":-1}}}"#.utf8)))
        XCTAssertThrowsError(try UsageDecoders.codexRateLimits(Data(#"{"rateLimits":{"primary":{"usedPercent":-1}}}"#.utf8)))
    }

    func testCodexSupportsLegacySingleBucketAndWeeklyWindow() throws {
        let input = Data(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1800003600},"secondary":{"usedPercent":60,"windowDurationMins":10080,"resetsAt":1800604800}}}"#.utf8)
        let result = try UsageDecoders.codexRateLimits(input, at: now)
        XCTAssertEqual(result.windows.map(\.name), ["5 hours", "7 days"])
        XCTAssertEqual(result.windows.map(\.usedPercent), [25, 60])
        XCTAssertEqual(result.windows[0].resetsAt, now.addingTimeInterval(3600))
    }

    func testCodexMultiBucketDoesNotDoubleCountLegacyView() throws {
        let input = Data(#"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25,"windowDurationMins":300}},"other":{"limitName":"Other models","secondary":{"usedPercent":42,"windowDurationMins":60}}}}"#.utf8)
        let result = try UsageDecoders.codexRateLimits(input)
        XCTAssertEqual(result.windows.count, 2)
        XCTAssertEqual(result.windows.map(\.usedPercent), [25, 42])
        XCTAssertEqual(result.windows[1].name, "Other models · 1 hour")
        XCTAssertEqual(Set(result.windows.map(\.id)).count, 2)
    }

    func testCodexMissingRateLimitsDoesNotBecomeZero() {
        for input in [#"{}"#, #"{"rateLimits":null}"#, #"{"rateLimits":{"primary":null,"secondary":null}}"#] {
            XCTAssertThrowsError(try UsageDecoders.codexRateLimits(Data(input.utf8)))
        }
    }

    func testInvalidInputIsRejected() {
        XCTAssertThrowsError(try UsageDecoders.claudeStatusLine(Data("broken".utf8)))
        XCTAssertThrowsError(try UsageDecoders.codexRateLimits(Data(#"{"rateLimits":{"primary":{"usedPercent":"many"}}}"#.utf8)))
    }

    func testOverLimitValuesRemainVisibleButProgressIsClamped() throws {
        let result = try UsageDecoders.codexRateLimits(Data(#"{"rateLimits":{"primary":{"usedPercent":105}}}"#.utf8))
        XCTAssertEqual(result.windows[0].usedPercent, 105)
        XCTAssertEqual(result.windows[0].fraction, 1)
    }

    func testExpiredReadingIsExcludedWithoutAssumingResetToZero() {
        let oldWindow = UsageWindow(name: "Session", usedPercent: 90, resetsAt: now)
        let plan = TrackedPlan(snapshot: UsageSnapshot(capturedAt: now, windows: [oldWindow]))
        XCTAssertTrue(oldWindow.hasReset(at: now))
        XCTAssertNil(plan.highestCurrentUsage(at: now))
        XCTAssertEqual(plan.snapshot?.windows[0].usedPercent, 90)
    }

    func testStaleAndFutureReadingsDoNotDriveMenuBarWarning() {
        let snapshot = UsageSnapshot(capturedAt: now, windows: [UsageWindow(name: "Weekly", usedPercent: 95)])
        let plan = TrackedPlan(snapshot: snapshot)
        XCTAssertEqual(plan.highestCurrentUsage(at: now), 0.95)
        XCTAssertNil(plan.highestCurrentUsage(at: now.addingTimeInterval(901)))
        XCTAssertNil(plan.highestCurrentUsage(at: now.addingTimeInterval(-61)))
    }

    func testUnknownAndNonfiniteValuesHaveNoProgressFraction() {
        let percentages: [Double?] = [nil, -Double.infinity, Double.infinity, Double.nan, -10]
        for percent in percentages {
            XCTAssertNil(UsageWindow(name: "Unknown", usedPercent: percent).fraction)
        }
    }
}
