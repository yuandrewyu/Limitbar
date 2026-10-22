import Foundation
import XCTest
@testable import LimitbarCore

final class CodexClientTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    private func executable(_ content: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent("fake-codex")
        try Data(("#!/bin/sh\n" + content).utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    func testHandshakeAndQuotaReadWithoutCreatingAModelTurn() async throws {
        let url = try executable(#"""
        phase=0
        while IFS= read -r line; do
            case "$line" in
                *'"initialize"'*)
                    [ "$phase" = 0 ] || exit 10
                    phase=1
                    printf '%s\n' '{"id":0,"result":{"userAgent":"test"}}'
                    ;;
                *'"initialized"'*)
                    [ "$phase" = 1 ] || exit 11
                    phase=2
                    ;;
                *'"account/read"'*)
                    [ "$phase" = 2 ] || exit 12
                    phase=3
                    printf '%s\n' '{"id":1,"result":{"account":{"type":"chatgpt","planType":"plus"}}}'
                    ;;
                *'"account/rateLimits/read"'*)
                    [ "$phase" = 3 ] || exit 13
                    printf '%s\n' '{"method":"account/updated","params":{"authMode":"chatgpt"}}'
                    printf '%s\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":37,"windowDurationMins":300}}}}'
                    ;;
                *) exit 14 ;;
            esac
        done
        """#)
        let result = try await CodexClient.fetch(executable: url, timeout: 3)
        XCTAssertEqual(result.windows.count, 1)
        XCTAssertEqual(result.windows[0].usedPercent, 37)
    }

    func testAPIKeyLoginIsNotReportedAsSubscriptionUsage() async throws {
        let url = try executable(#"""
        while IFS= read -r line; do
            case "$line" in
                *'"initialize"'*) printf '%s\n' '{"id":0,"result":{}}' ;;
                *'"account/read"'*) printf '%s\n' '{"id":1,"result":{"account":{"type":"apiKey"}}}' ;;
            esac
        done
        """#)
        do {
            _ = try await CodexClient.fetch(executable: url, timeout: 3)
            XCTFail("API-key usage must not be shown as a subscription limit")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("subscription"))
        }
    }

    func testNonresponsiveCLIHasABoundedWait() async throws {
        let url = try executable("while IFS= read -r line; do :; done\n")
        let started = Date()
        do {
            _ = try await CodexClient.fetch(executable: url, timeout: 0.3)
            XCTFail("A missing RPC response must time out")
        } catch {
            XCTAssertLessThan(Date().timeIntervalSince(started), 3)
            XCTAssertTrue(error.localizedDescription.contains("in time"))
        }
    }

    func testRPCErrorDoesNotExposeServerPayload() async throws {
        let url = try executable(#"""
        while IFS= read -r line; do
            printf '%s\n' '{"id":0,"error":{"code":-32000,"message":"private-account-details"}}'
        done
        """#)
        do {
            _ = try await CodexClient.fetch(executable: url, timeout: 3)
            XCTFail("An RPC error must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("-32000"))
            XCTAssertFalse(error.localizedDescription.contains("private-account-details"))
        }
    }
}
