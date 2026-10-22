import AppKit
import SwiftUI

struct WelcomeView: View {
    let close: () -> Void
    let managePlans: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Welcome to Limitbar", systemImage: "gauge.with.dots.needle.50percent")
                .font(.title2.bold())

            Text("Your AI usage limits and reset times, together in your menu bar.")
                .font(.title3)

            VStack(alignment: .leading, spacing: 12) {
                Label("Look for the small gauge icon near the clock at the top of your screen.",
                      systemImage: "menubar.arrow.up.rectangle")
                Label("Click it to see your plans, usage windows, and reset times.",
                      systemImage: "cursorarrow")
                Label("Open Manage plans to enter usage or set up a connection.",
                      systemImage: "slider.horizontal.3")
            }
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text("If your menu bar is crowded, close a few other menu bar apps to make room. You can reopen this window by opening Limitbar again.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Close", action: close)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Manage plans", action: managePlans)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 440)
    }
}
