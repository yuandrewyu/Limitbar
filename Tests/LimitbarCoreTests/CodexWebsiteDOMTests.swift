import XCTest
import WebKit
@testable import LimitbarCore

/// Synthetic HTML exercises the actual DOM adapter. These are not captured live-account fixtures.
@MainActor
final class CodexWebsiteDOMTests: XCTestCase {
    private func extract(_ html: String, origin: String = "https://chatgpt.com", path: String = "/codex/settings/usage") async throws -> String {
        let webView = WKWebView()
        webView.loadHTMLString(html, baseURL: nil)
        let deadline = Date().addingTimeInterval(10)
        while webView.isLoading && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        // Supply the usage-page location while exercising a real WebKit DOM with local fixtures.
        let script = "(() => { const location = {origin: '\(origin)', pathname: '\(path)'}; return \(CodexWebsiteScript.extractionScript); })()"
        let result = try await webView.evaluateJavaScript(script)
        return try XCTUnwrap(result as? String)
    }

    func testActualDOMExtractionAndPercentageDirection() async throws {
        let json = try await extract("""
        <section><div><h3>5 hour usage limit</h3></div><div><span>80%</span> <span>remaining</span></div>
        <p>Resets <time datetime="2026-10-22T20:00:00Z">at 4 PM</time></p></section>
        <section><h3>Weekly usage limit</h3><p>35% used</p></section>
        <input type="password" value="not-a-quota">
        """)
        let snapshot = try CodexWebsiteDecoder.decode(Data(json.utf8))
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [20, 35])
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
        XCTAssertFalse(json.contains("not-a-quota"))
    }

    func testMissingSessionPercentageDoesNotBorrowWeeklyValue() async throws {
        let json = try await extract("""
        <main><section><h3>5 hour usage limit</h3><p>Unavailable</p></section>
        <section><h3>Weekly usage limit</h3><p>60% remaining</p></section></main>
        """)
        let snapshot = try CodexWebsiteDecoder.decode(Data(json.utf8))
        XCTAssertEqual(snapshot.windows.map(\.id), ["website.weekly"])
    }

    func testOtherOriginAndLoginPageDoNotProduceReadings() async throws {
        let html = "<section><h3>Weekly usage limit</h3><p>60% remaining</p></section>"
        let foreign = try await extract(html, origin: "https://example.com")
        XCTAssertEqual(foreign, "[]")
        let login = try await extract("<h1>Log in</h1><p>Save 50% today</p><input type='password'>")
        XCTAssertEqual(login, "[]")
    }

    func testUnifiedUsagePageFromUserScreenshot() async throws {
        // Structure is representative; the labels and values match the reported screenshot.
        let json = try await extract("""
        <h1>Usage</h1><h2>Plan limits</h2>
        <section>
          <div><div>5-hour limit</div><div><span>Resets in 3h 29m</span><span>73% left</span></div><progress value="73" max="100"></progress></div>
          <div><div>Weekly limit</div><div><span>Resets in 6d 22h</span><span>96% left</span></div><progress value="96" max="100"></progress></div>
        </section>
        <h2>Recent plan usage</h2><div>73%</div>
        """, path: "/settings/usage")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = try CodexWebsiteDecoder.decode(Data(json.utf8), at: now)
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [27, 4])
        XCTAssertEqual(snapshot.windows.map(\.resetIsApproximate), [true, true])
        XCTAssertEqual(snapshot.windows[0].resetsAt, now.addingTimeInterval(3 * 3600 + 29 * 60))
        XCTAssertEqual(snapshot.windows[1].resetsAt, now.addingTimeInterval(6 * 86400 + 22 * 3600))
    }

    func testUnrelatedPageIsNotReadEvenWithQuotaLikeText() async throws {
        let json = try await extract("<h3>Weekly limit</h3><p>60% left</p>", path: "/")
        XCTAssertEqual(json, "[]")
    }
}
