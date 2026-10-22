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
    let maximumHeight: CGFloat
    let managePlans: () -> Void
    @State private var contentHeight: CGFloat = 1

    var body: some View {
        ScrollView {
            panelContent
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: DashboardHeightKey.self, value: geometry.size.height)
                    }
                }
        }
        .frame(width: 400, height: min(contentHeight, max(1, maximumHeight)))
        .onPreferenceChange(DashboardHeightKey.self) { contentHeight = $0 }
    }

    private var panelContent: some View {
        VStack(spacing: 0) {
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
                    Button("Add your first plan", action: managePlans)
                        .buttonStyle(.borderedProminent)
                }
                .padding(28)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 0) {
                        ForEach(store.plans) { plan in
                            PlanCard(plan: plan, error: store.refreshErrors[plan.id], now: context.date)
                            if plan.id != store.plans.last?.id { Divider() }
                        }
                    }
                }
            }

            Divider()
            HStack(spacing: 12) {
                Button(action: managePlans) { Label("Manage plans", systemImage: "slider.horizontal.3") }
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
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(width: 400)
    }
}

private struct DashboardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 1
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@MainActor
struct PlanCard: View {
    let plan: TrackedPlan
    let error: String?
    let now: Date

    private var title: String {
        if plan.source == .codex || plan.source == .codexWeb { return "Codex" }
        return plan.provider == .other ? plan.displayName : plan.provider.name
    }

    private var sourceLabel: String {
        switch plan.source {
        case .manual: return "Manual"
        case .claudeWeb, .codexWeb: return "Website"
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex CLI"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                ProviderIcon(provider: plan.provider)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text("\(sourceLabel) · \(plan.displayName)")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help("\(plan.displayName) · \(plan.source.name)")
                }
                Spacer(minLength: 4)
                if let snapshot = plan.snapshot {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(snapshot.isStale(at: now) || error != nil ? "Last reading" : "Updated")
                        Text(snapshot.capturedAt, style: .relative)
                    }
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .help("Last captured: \(snapshot.capturedAt.formatted()). Readings older than 15 minutes are stale.")
                }
                if plan.provider != .other {
                    Link(destination: plan.website) { Image(systemName: "arrow.up.right") }
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .help("Open \(title) usage page")
                        .accessibilityLabel("Open \(title) usage page")
                }
            }

            if let snapshot = plan.snapshot, !snapshot.windows.isEmpty {
                ForEach(snapshot.windows) { window in
                    windowView(window, stale: snapshot.isStale(at: now) || error != nil)
                }
            } else {
                Text("Usage unavailable · Manage plans to connect")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .help(plan.source == .manual ? "Enter usage manually or select a website connection in Manage plans."
                          : "Open Manage plans → Connections to sign in.")
            }

            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 10)).foregroundStyle(.orange)
                    .lineLimit(2).help(error)
                    .accessibilityLabel(error)
            } else if plan.snapshot?.isStale(at: now) == true {
                Text("Stale reading · awaiting an update")
                    .font(.system(size: 10)).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func shortName(_ window: UsageWindow) -> String {
        switch window.name {
        case "5 hours": return "5-hour"
        case "Current session": return "Session"
        case "Weekly", "This week", "7 days": return "Week"
        default: return window.name
        }
    }

    private func windowView(_ window: UsageWindow, stale: Bool) -> some View {
        let reset = window.hasReset(at: now)
        let fraction = window.fraction
        let tint: Color = reset || stale ? .secondary : (fraction ?? 0) >= 0.9 ? .orange : plan.provider.tint
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(shortName(window))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(stale || reset ? .secondary : .primary)
                    .lineLimit(2)
                if reset {
                    Text("Awaiting update").foregroundStyle(.orange)
                        .font(.system(size: 9))
                } else if let date = window.resetsAt {
                    Text("resets \(window.resetIsApproximate == true ? "≈ " : "")\(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .help((window.resetIsApproximate == true ? "Estimated from the website’s reset display. " : "") + date.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("Reset unknown").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 132, alignment: .leading)

            GeometryReader { geometry in
                Capsule().fill(Color.primary.opacity(0.13))
                    .overlay(alignment: .leading) {
                        if let fraction {
                            Capsule().fill(tint).frame(width: geometry.size.width * fraction)
                        }
                    }
            }
            .frame(height: 4)
            .accessibilityHidden(true)

            Group {
                if let percent = window.usedPercent, fraction != nil {
                    Text("\(percent.formatted(.number.precision(.fractionLength(0...1))))%")
                        .foregroundStyle(stale || reset ? .secondary : .primary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .frame(width: 42, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(fraction == nil ? "Usage unknown" : "\(window.usedPercent ?? 0) percent used\(stale || reset ? ", last known reading" : "")")
        .help("\(window.name): \(fraction == nil ? "unknown usage" : "percentage used")")
    }
}
