import SwiftUI
import LimitbarCore

@MainActor
struct PlanEditor: View {
    @ObservedObject var store: UsageStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TrackedPlan
    @State private var entryError: String?

    init(store: UsageStore, plan: TrackedPlan) {
        self.store = store
        _draft = State(initialValue: plan)
    }

    private var availableSources: [UsageSource] {
        draft.provider.availableSources
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
                        ForEach(Provider.allCases.filter { !$0.availableSources.isEmpty }) {
                            Text($0 == .chatgpt ? "Codex" : $0.name).tag($0)
                        }
                    }
                    TextField("Plan name", text: $draft.name, prompt: Text("e.g. Claude Pro · Personal"))
                    Picker("Usage source", selection: $draft.source) {
                        ForEach(availableSources) { Text($0.name).tag($0) }
                    }
                } footer: {
                    Text("Use your actual plan name. Limitbar does not assume a tier or a fixed message allowance.")
                }

                if draft.source == .claudeWeb {
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
                        Text("Each source connects one account. Credentials stay with the official coding tool.")
                    }
                }
                if let entryError {
                    Section { Text(entryError).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .onChange(of: draft.provider) { _, _ in
                if !availableSources.contains(draft.source), let source = availableSources.first { draft.source = source }
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
        .frame(width: 540, height: 390)
    }

    private func save() {
        guard !store.automaticSourceInUse(draft.source, except: draft.id) else {
            entryError = "This source is already connected to a plan. Edit the existing plan instead."
            return
        }
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.plans.first(where: { $0.id == draft.id })?.source != draft.source {
            draft.snapshot = nil
        }
        if store.save(draft) { dismiss() }
        else { entryError = store.storageError ?? "Your changes could not be saved." }
    }
}
