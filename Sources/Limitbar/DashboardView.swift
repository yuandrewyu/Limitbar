import AppKit
import SwiftUI
import LimitbarCore

extension Provider {
    var tint: Color {
        switch self {
        case .claude: return Color(red: 0.80, green: 0.43, blue: 0.30)
        case .chatgpt: return Color(red: 0.12, green: 0.62, blue: 0.48)
        case .gemini: return Color(red: 0.34, green: 0.48, blue: 0.88)
        case .other: return .purple
        }
    }

    var symbol: String {
        switch self {
        case .claude: return "sun.max"
        case .chatgpt: return "bubble.left.and.bubble.right"
        case .gemini: return "sparkles"
        case .other: return "square.stack.3d.up"
        }
    }
}

@MainActor
struct DashboardView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Limitbar").font(.headline)
                    Text("Your AI, at a glance.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("ON THIS MAC")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .tracking(1).foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            if let error = store.storageError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal, 20).padding(.top, 12)
            }

            if store.plans.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
                    Text("One place for your AI plans").font(.headline)
                    Text("Add your subscriptions to see usage windows and reset times here.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    SettingsLink { Text("Add your first plan") }
                        .buttonStyle(.borderedProminent)
                        .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
                }
                .padding(28)
            } else {
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        LazyVStack(spacing: 12) {
                            ForEach(store.plans) { plan in
                                PlanCard(plan: plan, error: store.refreshErrors[plan.id], now: context.date)
                            }
                        }
                        .padding(16)
                    }
                }
                .frame(maxHeight: 470)
            }

            Divider()
            HStack(spacing: 12) {
                SettingsLink { Label("Manage plans", systemImage: "slider.horizontal.3") }
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    if store.refreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(store.refreshing)
                .help("Read connected sources again. Manual entries stay as entered.")
                .accessibilityLabel("Refresh connected sources")
                Menu {
                    Button("Open data folder") { store.showDataFolder() }
                    Button("Quit Limitbar", role: .destructive) { NSApp.terminate(nil) }
                        .keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("More options")
            }
            .font(.caption)
            .buttonStyle(.plain)
            .padding(.horizontal, 18).padding(.vertical, 14)
        }
        .frame(width: 370)
    }
}

@MainActor
struct PlanCard: View {
    let plan: TrackedPlan
    let error: String?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: plan.provider.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(plan.provider.tint)
                    .frame(width: 34, height: 34)
                    .background(plan.provider.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.displayName).font(.system(.callout, design: .rounded, weight: .semibold))
                    Text(plan.source == .codex ? "Codex allowance · ChatGPT plan" : plan.provider.name)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if plan.provider != .other {
                    Link(destination: plan.website) { Image(systemName: "arrow.up.right") }
                        .font(.caption).foregroundStyle(.secondary)
                        .help("Open \(plan.provider.name) in your browser")
                        .accessibilityLabel("Open \(plan.provider.name) usage page")
                }
            }

            if let snapshot = plan.snapshot, !snapshot.windows.isEmpty {
                ForEach(snapshot.windows) { window in
                    windowView(window, stale: snapshot.isStale(at: now) || error != nil)
                }
                HStack(spacing: 4) {
                    Image(systemName: plan.source == .manual ? "pencil" : "link")
                    Text(plan.source == .manual ? "Manual entry" : "From \(plan.source == .codex ? "Codex CLI" : "Claude Code")")
                    Text("·")
                    Text(snapshot.capturedAt, style: .relative)
                    if snapshot.isStale(at: now) { Text("· Stale").foregroundStyle(.orange) }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .help("Last captured: \(snapshot.capturedAt.formatted()). Readings older than 15 minutes are stale.")
            } else {
                Label("Usage not available", systemImage: "minus.circle")
                    .font(.callout).foregroundStyle(.secondary)
                Text(plan.source == .manual
                     ? "Enter the usage shown by your provider in Manage plans."
                     : "Connect your local coding tool in Manage plans.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.07)) }
    }

    @ViewBuilder
    private func windowView(_ window: UsageWindow, stale: Bool) -> some View {
        let reset = window.hasReset(at: now)
        let fraction = window.fraction
        let tint: Color = reset || stale ? .secondary : (fraction ?? 0) >= 0.9 ? .orange : plan.provider.tint
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(window.name).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let percent = window.usedPercent, fraction != nil {
                    Text("\(percent.formatted(.number.precision(.fractionLength(0...1))))% used")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                } else { Text("Unknown").font(.caption).foregroundStyle(.secondary) }
            }
            if let fraction {
                ProgressView(value: fraction).tint(tint)
                    .accessibilityLabel("\(window.name), \(window.usedPercent ?? 0) percent used\(stale || reset ? ", last known reading" : "")")
            }
            if reset {
                Text("Reset time passed · awaiting a new reading")
                    .font(.system(size: 10)).foregroundStyle(.orange)
            } else if let date = window.resetsAt {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                    Text("Resets in")
                    Text(date, style: .relative)
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .help(date.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }
}
