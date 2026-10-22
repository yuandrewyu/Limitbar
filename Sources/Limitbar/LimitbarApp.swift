import AppKit
import SwiftUI
import LimitbarCore

@main
@MainActor
struct LimitbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(store: store)
        } label: {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let worst = store.plans.compactMap { plan -> Double? in
                    guard store.refreshErrors[plan.id] == nil else { return nil }
                    return plan.highestCurrentUsage(at: context.date)
                }.max()
                Image(systemName: worst.map { $0 >= 0.9 } == true
                      ? "gauge.with.dots.needle.100percent" : "gauge.with.dots.needle.50percent")
                    .accessibilityLabel("Limitbar AI subscription usage")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
