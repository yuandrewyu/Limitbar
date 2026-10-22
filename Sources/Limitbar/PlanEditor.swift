import SwiftUI
import LimitbarCore

@MainActor
struct PlanEditor: View {
    @ObservedObject var store: UsageStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TrackedPlan
    @State private var windows: [UsageWindow]
    @State private var entryError: String?

    init(store: UsageStore, plan: TrackedPlan) {
        self.store = store
        _draft = State(initialValue: plan)
        _windows = State(initialValue: plan.source == .manual ? plan.snapshot?.windows ?? [] : [])
    }

    private var availableSources: [UsageSource] {
        switch draft.provider {
        case .claude: return [.manual, .claudeCode, .claudeWeb]
        case .chatgpt: return [.manual, .codex, .codexWeb]
        default: return [.manual]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Subscription details").font(.title3.bold())
                Spacer()
            }.padding(20)
            Divider()
            Form {
                Section {
                    Picker("Service", selection: $draft.provider) {
                        ForEach(Provider.allCases) { Text($0.name).tag($0) }
                    }
                    TextField("Plan name", text: $draft.name, prompt: Text("e.g. Claude Pro · Personal"))
                    Picker("Usage source", selection: $draft.source) {
                        ForEach(availableSources) { Text($0.name).tag($0) }
                    }
                } footer: {
                    Text("Use your actual plan name. Limitbar does not assume a tier or a fixed message allowance.")
                }

                if draft.source == .manual {
                    Section {
                        ForEach($windows) { $window in
                            ManualWindowEditor(window: $window) {
                                windows.removeAll { $0.id == window.id }
                            }
                        }
                        Button("Add a usage window", systemImage: "plus") {
                            windows.append(UsageWindow(name: windows.isEmpty ? "Current window" : "Weekly"))
                        }
                    } header: {
                        Text("Usage windows")
                    } footer: {
                        Text("Copy the percentage USED from the provider. Leave it blank if unknown. Add separate windows for session, weekly, or model-specific limits.")
                    }
                } else if draft.source == .claudeWeb {
                    Section {
                        Text("Reads Current session and This week from Claude’s usage settings after you sign in. Local clock reset dates are inferred and marked approximate.")
                        Button("Open Claude website connection…") { store.showClaudeWebsite() }
                    }
                } else if draft.source == .codexWeb {
                    Section {
                        Text("Reads the Codex usage page after you sign in. This prototype supports English usage cards and keeps unreadable values unknown.")
                        Button("Open Codex website connection…") { store.showCodexWebsite() }
                    }
                } else {
                    Section {
                        Label(draft.source == .codex ? "Reads the active Codex CLI account" : "Reads the Claude Code status line bridge",
                              systemImage: "link")
                        Text(draft.source == .codex
                             ? "Tracks the Codex allowance included with your ChatGPT subscription. Regular ChatGPT chats can have separate limits. Install Codex CLI yourself and run codex login first."
                             : "Requires a Claude Code version that reports subscription rate limits. Enable the bridge using the instructions in Settings. Readings update while you use Claude Code.")
                            .font(.callout).foregroundStyle(.secondary)
                    } footer: {
                        Text("One automatic connection per service. For other accounts, use manual tracking. The app does not collect passwords or browser cookies.")
                    }
                }
                if let entryError {
                    Section { Text(entryError).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .onChange(of: draft.provider) { _, _ in
                if !availableSources.contains(draft.source) { draft.source = .manual }
            }

            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save plan", action: save).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!store.loadedSafely)
            }.padding(16)
        }
        .frame(width: 540, height: 600)
    }

    private func save() {
        guard !store.automaticSourceInUse(draft.source, except: draft.id) else {
            entryError = "This automatic source is already connected to a plan. Edit that plan or choose manual entry."
            return
        }
        guard windows.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) || draft.source != .manual else {
            entryError = "Give each usage window a name."
            return
        }
        guard windows.allSatisfy({ window in
            guard let value = window.usedPercent else { return true }
            return value.isFinite && (0...100).contains(value)
        }) || draft.source != .manual else {
            entryError = "Usage must be a percentage from 0 to 100, or left blank."
            return
        }
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.source == .manual {
            draft.snapshot = windows.isEmpty ? nil : UsageSnapshot(windows: windows)
        } else if store.plans.first(where: { $0.id == draft.id })?.source != draft.source {
            draft.snapshot = nil
        }
        if store.save(draft) { dismiss() }
        else { entryError = store.storageError ?? "Your changes could not be saved." }
    }
}

@MainActor
private struct ManualWindowEditor: View {
    @Binding var window: UsageWindow
    let remove: () -> Void
    @State private var percentText = ""
    @State private var invalidNumber = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Window name", text: $window.name, prompt: Text("e.g. 5 hours"))
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash")
                }.buttonStyle(.borderless).help("Remove usage window")
            }
            HStack {
                TextField("Used (%)", text: $percentText, prompt: Text("Unknown"))
                    .onChange(of: percentText) { _, text in
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            window.usedPercent = nil
                            invalidNumber = false
                        } else if let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")),
                                  value.isFinite, (0...100).contains(value) {
                            window.usedPercent = value
                            invalidNumber = false
                        } else {
                            // NaN keeps the parent Save validation from accepting an invalid edit.
                            window.usedPercent = .nan
                            invalidNumber = true
                        }
                    }
                if invalidNumber {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.red)
                        .help("Enter a number from 0 to 100")
                }
            }
            Toggle("Known reset time", isOn: Binding(
                get: { window.resetsAt != nil },
                set: { window.resetsAt = $0 ? Date().addingTimeInterval(5 * 3600) : nil }
            ))
            if window.resetsAt != nil {
                DatePicker("Resets", selection: Binding(
                    get: { window.resetsAt ?? Date() },
                    set: { window.resetsAt = $0 }
                ))
            }
        }
        .padding(.vertical, 6)
        .onAppear {
            percentText = window.usedPercent.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US_POSIX"))) } ?? ""
        }
    }
}
