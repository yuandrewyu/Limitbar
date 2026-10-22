import AppKit
import Combine
import Foundation
import LimitbarCore

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var configuration = PlanConfiguration()
    @Published private(set) var refreshErrors: [UUID: String] = [:]
    @Published private(set) var refreshing = false
    @Published private(set) var storageError: String?
    @Published private(set) var loadedSafely = false
    private let repository = PlanRepository()
    private var refreshTask: Task<Void, Never>?

    var plans: [TrackedPlan] { configuration.plans }

    init() {
        reload()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(60)) }
                catch { break }
            }
        }
    }

    func reload() {
        do {
            configuration = try repository.load()
            storageError = nil
            loadedSafely = true
            if !FileManager.default.fileExists(atPath: repository.fileURL.path) {
                configuration.plans = [
                    TrackedPlan(provider: .claude, name: "Claude subscription"),
                    TrackedPlan(provider: .chatgpt, name: "ChatGPT subscription"),
                    TrackedPlan(provider: .gemini, name: "Google AI subscription")
                ]
                _ = commit(configuration)
            }
        } catch {
            loadedSafely = false
            storageError = "Your saved plans could not be read. The file has been left untouched. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func save(_ plan: TrackedPlan) -> Bool {
        guard loadedSafely else { return false }
        var updated = configuration
        if let index = updated.plans.firstIndex(where: { $0.id == plan.id }) {
            updated.plans[index] = plan
        } else { updated.plans.append(plan) }
        guard commit(updated) else { return false }
        refreshErrors[plan.id] = nil
        Task { await refresh() }
        return true
    }

    func remove(_ id: UUID) {
        var updated = configuration
        updated.plans.removeAll { $0.id == id }
        if commit(updated) { refreshErrors[id] = nil }
    }

    func setCodexExecutable(_ path: String) {
        var updated = configuration
        updated.codexExecutable = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if commit(updated) { Task { await refresh() } }
    }

    func automaticSourceInUse(_ source: UsageSource, except id: UUID) -> Bool {
        source != .manual && plans.contains { $0.id != id && $0.source == source }
    }

    func showDataFolder() {
        let directory = LimitbarPaths.directory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directory)
        } catch { storageError = error.localizedDescription }
    }

    func refresh() async {
        guard loadedSafely, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        // Capture IDs and settings; a plan may be edited or deleted while an RPC is in flight.
        let requests = plans.filter { $0.source != .manual }
        let executable = configuration.codexExecutable
        var changed = false
        for plan in requests {
            do {
                let snapshot: UsageSnapshot
                switch plan.source {
                case .manual: continue
                case .claudeCode:
                    guard FileManager.default.fileExists(atPath: LimitbarPaths.claudeSnapshot.path) else {
                        throw StoreError.message("Waiting for Claude Code. Set up the status line bridge in Settings, then use Claude Code.")
                    }
                    let data = try Data(contentsOf: LimitbarPaths.claudeSnapshot)
                    guard data.count < 256 * 1024 else {
                        throw StoreError.message("The Claude usage file is larger than expected.")
                    }
                    snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: data)
                    guard !snapshot.windows.isEmpty else {
                        throw StoreError.message("Claude Code has not reported subscription limits. Use a supported version signed in with your subscription.")
                    }
                case .codex:
                    snapshot = try await CodexClient.fetch(executable: CodexClient.findExecutable(override: executable))
                }
                guard let index = configuration.plans.firstIndex(where: {
                    $0.id == plan.id && $0.source == plan.source
                }) else { continue }
                if configuration.plans[index].snapshot != snapshot {
                    configuration.plans[index].snapshot = snapshot
                    changed = true
                }
                refreshErrors[plan.id] = nil
            } catch {
                if configuration.plans.contains(where: { $0.id == plan.id && $0.source == plan.source }) {
                    refreshErrors[plan.id] = error.localizedDescription
                }
            }
        }
        if changed { _ = commit(configuration) }
    }

    @discardableResult
    private func commit(_ updated: PlanConfiguration) -> Bool {
        guard loadedSafely else { return false }
        do {
            try repository.save(updated)
            configuration = updated
            storageError = nil
            return true
        } catch {
            storageError = "Could not save your changes: \(error.localizedDescription)"
            return false
        }
    }
}

private enum StoreError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
