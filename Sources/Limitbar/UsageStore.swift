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
    lazy var codexWebsite = WebsiteConnection(service: .codex)
    lazy var claudeWebsite = WebsiteConnection(service: .claude)

    var plans: [TrackedPlan] { configuration.plans.filter { $0.source != .manual } }

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
            var updated = configuration
            if updated.archiveManualPlans() { _ = commit(updated) }
        } catch {
            loadedSafely = false
            storageError = "Your saved plans could not be read. The file has been left untouched. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func save(_ plan: TrackedPlan) -> Bool {
        guard loadedSafely, plan.provider.availableSources.contains(plan.source) else { return false }
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

    func showCodexWebsite() {
        codexWebsite.show(store: self)
    }

    func showClaudeWebsite() {
        claudeWebsite.show(store: self)
    }

    private func website(_ service: WebsiteService) -> WebsiteConnection {
        service == .codex ? codexWebsite : claudeWebsite
    }

    func connectWebsite(_ service: WebsiteService) async {
        guard loadedSafely, !refreshing else { return }
        let connection = website(service)
        refreshing = true
        defer { refreshing = false }
        do {
            let snapshot = try await connection.read(reload: false)
            var updated = configuration
            if let index = updated.plans.firstIndex(where: { $0.source == service.source }) {
                updated.plans[index].snapshot = snapshot
            } else {
                updated.plans.append(TrackedPlan(provider: service.provider, name: "\(service.name) · Website",
                                                 source: service.source, snapshot: snapshot))
            }
            if commit(updated) {
                for plan in plans where plan.source == service.source { refreshErrors[plan.id] = nil }
                connection.status = "Connected. Read \(snapshot.windows.count) usage window(s). Limitbar will reload the usage page every minute."
            } else { connection.status = storageError ?? "Could not save the connection." }
        } catch { connection.status = error.localizedDescription }
    }

    func disconnectWebsite(_ service: WebsiteService) async {
        let connection = website(service)
        guard loadedSafely, !refreshing, !connection.reading else { return }
        refreshing = true
        defer { refreshing = false }
        var updated = configuration
        updated.plans.removeAll { $0.source == service.source }
        guard commit(updated) else { return }
        refreshErrors = refreshErrors.filter { id, _ in plans.contains { $0.id == id && $0.source != .manual } }
        await connection.clearSession()
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
                case .codexWeb:
                    snapshot = try await codexWebsite.read(reload: true)
                case .claudeWeb:
                    snapshot = try await claudeWebsite.read(reload: true)
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
