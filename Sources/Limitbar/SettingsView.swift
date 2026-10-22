import AppKit
import SwiftUI
import LimitbarCore

@MainActor
struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @State private var editing: TrackedPlan?
    @State private var deleting: TrackedPlan?
    @State private var codexPath = ""
    @State private var copied = false

    private var bridgePath: String {
        Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("LimitbarBridge").path ?? ""
    }

    private var bridgeConfiguration: String {
        let command = "'" + bridgePath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let object: [String: Any] = ["statusLine": ["type": "command", "command": command]]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    var body: some View {
        TabView {
            plansTab.tabItem { Label("Plans", systemImage: "square.stack.3d.up") }
            connectionsTab.tabItem { Label("Connections", systemImage: "link") }
        }
        .padding(16)
        .frame(width: 620, height: 560)
        .sheet(item: $editing) { PlanEditor(store: store, plan: $0) }
        .alert("Remove this plan?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), presenting: deleting) { plan in
            Button("Remove", role: .destructive) { store.remove(plan.id); deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { plan in
            Text("This removes \(plan.displayName) from Limitbar. Your subscription is unaffected.")
        }
    }

    private var plansTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your subscriptions").font(.title2.bold())
                    Text("Track each plan and its individual usage windows.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    ForEach(Provider.allCases) { provider in
                        Button(provider.name) {
                            editing = TrackedPlan(provider: provider)
                        }
                    }
                } label: { Label("Add plan", systemImage: "plus") }
                .disabled(!store.loadedSafely)
            }
            if let error = store.storageError {
                VStack(alignment: .leading, spacing: 6) {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    HStack {
                        Button("Open data folder") { store.showDataFolder() }
                        Button("Retry loading") { store.reload() }
                    }
                }.font(.caption)
            }
            List {
                ForEach(store.plans) { plan in
                    HStack(spacing: 12) {
                        ProviderIcon(provider: plan.provider, size: 20)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plan.displayName).font(.headline)
                            Text("\(plan.provider.name) · \(plan.source.name)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { editing = plan }
                        Button(role: .destructive) { deleting = plan } label: {
                            Image(systemName: "trash")
                        }.help("Remove \(plan.displayName)")
                    }
                    .padding(.vertical, 9)
                }
            }
            .overlay {
                if store.plans.isEmpty {
                    ContentUnavailableView("No plans yet", systemImage: "square.stack.3d.up",
                                           description: Text("Add Claude, ChatGPT, Google, or another subscription."))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .disabled(!store.loadedSafely)
            Text("Manual entries are labeled in the menu panel. Connected sources are checked every minute while the app runs. No telemetry or third-party libraries.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var connectionsTab: some View {
        Form {
            Section("Codex website · Prototype") {
                Text("Connect through the Codex usage website without installing the CLI. Sign in in Limitbar’s browser, then click Read usage & connect. A separate Codex plan is added after a successful reading.")
                    .font(.callout)
                Button("Connect Codex website…") { store.showCodexWebsite() }
                    .disabled(!store.loadedSafely)
                Button("Disconnect and clear website session") {
                    Task { await store.disconnectWebsite(.codex) }
                }
                .disabled(!store.loadedSafely || store.refreshing || store.codexWebsite.reading)
                Text("Experimental: reads English usage cards and refreshes every minute. Website changes or blocked embedded sign-in can prevent connection. Existing manual and CLI plans are preserved.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Claude website · Prototype") {
                Text("Sign in to Claude inside Limitbar, open Your usage, then click Read usage & connect. A separate Claude plan is added after a successful reading; no Claude Code installation is needed.")
                    .font(.callout)
                Button("Connect Claude website…") { store.showClaudeWebsite() }
                    .disabled(!store.loadedSafely)
                Button("Disconnect and clear Claude website session") {
                    Task { await store.disconnectWebsite(.claude) }
                }
                .disabled(!store.loadedSafely || store.refreshing || store.claudeWebsite.reading)
                Text("Reads Current session and This week, with automatic refresh every minute. Clock-based reset dates use your Mac’s local time zone and are marked approximate. Claude and Codex sign-in sessions are kept separately.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Claude Code") {
                Text("To receive subscription limits from Claude Code, add this statusLine entry to ~/.claude/settings.json on your Mac, then start a new Claude Code session.")
                    .font(.callout)
                Text(bridgeConfiguration)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                Button(copied ? "Copied" : "Copy configuration") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bridgeConfiguration, forType: .string)
                    copied = true
                }
                Text("Merge this entry with your existing settings. It replaces an existing status line if you already have one. Use a version of Claude Code that reports rate_limits, signed in with your subscription. Select ‘Claude Code status line’ when editing your Claude plan.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Codex · included with ChatGPT") {
                Text("Install the official Codex CLI yourself and run codex login. Limitbar reads its active ChatGPT account using the documented app-server protocol. This reports Codex limits, which may differ from regular ChatGPT chat limits.")
                    .font(.callout)
                TextField("Codex executable", text: $codexPath, prompt: Text("Automatic detection"))
                Button("Save executable path") { store.setCodexExecutable(codexPath) }
                    .disabled(!store.loadedSafely)
                Text("Leave blank for standard Homebrew and local install locations. Otherwise paste the absolute path returned by ‘which codex’ in Terminal. Select ‘Codex CLI’ when editing your ChatGPT plan.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Web subscriptions") {
                Text("Use manual entries for Google AI and regular ChatGPT chat limits. The Claude and Codex website readers above are experimental connections to their subscription usage pages.")
                    .font(.callout)
            }
            Section("Local data") {
                Button("Open Limitbar data folder") { store.showDataFolder() }
                Text("Saved plans and quota snapshots stay in Application Support/Limitbar. Website sign-in uses Limitbar’s local WebKit session; it does not import browser cookies. The app saves only extracted quota values, not website contents or passwords. CLI credentials remain with the CLI.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { codexPath = store.configuration.codexExecutable }
    }
}
