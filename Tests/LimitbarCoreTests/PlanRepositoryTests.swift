import Foundation
import XCTest
@testable import LimitbarCore

final class PlanRepositoryTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var repository: PlanRepository!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        repository = PlanRepository(fileURL: temporaryDirectory.appendingPathComponent("plans.json"))
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: temporaryDirectory.path) {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testFirstLaunchHasNoInventedUsage() throws {
        let result = try repository.load()
        XCTAssertTrue(result.plans.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.fileURL.path))
    }

    func testPlansAndMultipleWindowsRoundTrip() throws {
        let windows = [UsageWindow(name: "Session", usedPercent: 33, resetsAt: Date(timeIntervalSince1970: 1_800_000_000)),
                       UsageWindow(name: "Weekly")]
        let plan = TrackedPlan(provider: .claude, name: "Personal plan", source: .manual,
                               snapshot: UsageSnapshot(windows: windows))
        try repository.save(PlanConfiguration(plans: [plan], codexExecutable: "/usr/local/bin/codex"))
        let result = try repository.load()
        XCTAssertEqual(result.plans, [plan])
        XCTAssertEqual(result.codexExecutable, "/usr/local/bin/codex")
        let attributes = try FileManager.default.attributesOfItem(atPath: repository.fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testCorruptFileFailsWithoutReplacingUserData() throws {
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let original = Data("{not valid json".utf8)
        try original.write(to: repository.fileURL)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), original)
    }

    func testUnsupportedSchemaIsNotSilentlyAccepted() throws {
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let original = Data(#"{"version":2,"plans":[],"codexExecutable":""}"#.utf8)
        try original.write(to: repository.fileURL)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), original)
    }

    func testManualMigrationPreservesDataAndConnectedPlans() throws {
        let entered = TrackedPlan(provider: .claude, name: "Old manual plan", source: .manual,
                                  snapshot: UsageSnapshot(windows: [UsageWindow(name: "Weekly", usedPercent: 42)]))
        let placeholder = TrackedPlan(provider: .gemini, source: .manual)
        let connected = TrackedPlan(provider: .claude, name: "Claude", source: .claudeWeb,
                                    snapshot: UsageSnapshot(windows: [UsageWindow(name: "Session", usedPercent: 7)]))
        var configuration = PlanConfiguration(plans: [entered, placeholder, connected], codexExecutable: "/usr/local/bin/codex")
        XCTAssertTrue(configuration.archiveManualPlans())
        XCTAssertEqual(configuration.plans, [connected])
        XCTAssertEqual(configuration.archivedManualPlans, [entered, placeholder])
        XCTAssertFalse(configuration.archiveManualPlans())
        XCTAssertEqual(configuration.archivedManualPlans, [entered, placeholder])
        try repository.save(configuration)
        let loaded = try repository.load()
        XCTAssertEqual(loaded.plans, [connected])
        XCTAssertEqual(loaded.archivedManualPlans, [entered, placeholder])
        XCTAssertEqual(loaded.codexExecutable, "/usr/local/bin/codex")
    }

    func testOldConfigurationWithoutArchiveRemainsReadable() throws {
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try Data(#"{"version":1,"plans":[],"codexExecutable":""}"#.utf8).write(to: repository.fileURL)
        let loaded = try repository.load()
        XCTAssertNil(loaded.archivedManualPlans)
        XCTAssertTrue(loaded.plans.isEmpty)
    }

    func testNewSupportedSubscriptionsUseAutomaticSources() {
        XCTAssertEqual(TrackedPlan(provider: .claude).source, .claudeWeb)
        XCTAssertEqual(TrackedPlan(provider: .chatgpt).source, .codexWeb)
        XCTAssertFalse(Provider.claude.availableSources.contains(.manual))
        XCTAssertFalse(Provider.chatgpt.availableSources.contains(.manual))
        XCTAssertTrue(Provider.gemini.availableSources.isEmpty)
        XCTAssertTrue(Provider.other.availableSources.isEmpty)
    }
}
