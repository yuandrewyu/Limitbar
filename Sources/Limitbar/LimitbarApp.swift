import AppKit
import Combine
import SwiftUI
import LimitbarCore

@main
@MainActor
struct LimitbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView(store: delegate.store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var dashboardController: NSHostingController<DashboardView>?
    private var welcomeWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true
        item.button?.title = ""
        item.button?.imagePosition = .imageOnly
        item.button?.setAccessibilityLabel("Limitbar AI subscription usage")
        item.button?.toolTip = "Limitbar — AI subscription usage"
        item.button?.target = self
        item.button?.action = #selector(toggleDashboard)
        statusItem = item
        updateStatusIcon()

        popover.behavior = .transient
        let controller = NSHostingController(rootView: dashboard())
        controller.sizingOptions = [.preferredContentSize]
        dashboardController = controller
        popover.contentViewController = controller

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusIcon() }
            .store(in: &subscriptions)
        Timer.publish(every: 60, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.updateStatusIcon() }
            .store(in: &subscriptions)

        if !UserDefaults.standard.bool(forKey: "hasSeenNativeWelcome") {
            showWelcome()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWelcome()
        return false
    }

    private func updateStatusIcon() {
        let worst = store.plans.compactMap { plan -> Double? in
            guard store.refreshErrors[plan.id] == nil else { return nil }
            return plan.highestCurrentUsage(at: .now)
        }.max()
        let symbol = worst.map { $0 >= 0.9 } == true
            ? "gauge.with.dots.needle.100percent" : "gauge.with.dots.needle.50percent"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "AI subscription usage")
        image?.isTemplate = true
        image?.size = NSSize(width: 16, height: 16)
        statusItem?.button?.image = image
    }

    @objc private func toggleDashboard() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem?.button {
            dashboardController?.rootView = dashboard()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func dashboard() -> DashboardView {
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        let availableHeight = (screen?.visibleFrame.height ?? 800) - 32
        return DashboardView(store: store, maximumHeight: availableHeight,
                             managePlans: { [weak self] in self?.showSettings() })
    }

    private func showWelcome() {
        if welcomeWindow == nil {
            let view = WelcomeView(
                close: { [weak self] in self?.welcomeWindow?.close() },
                managePlans: { [weak self] in self?.showSettings() }
            )
            welcomeWindow = makeWindow(title: "Welcome to Limitbar", rootView: view)
        }
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow?.makeKeyAndOrderFront(nil)
        UserDefaults.standard.set(true, forKey: "hasSeenNativeWelcome")
    }

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Limitbar — Manage plans", rootView: SettingsView(store: store))
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow<Content: View>(title: String, rootView: Content) -> NSWindow {
        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(controller.view.fittingSize)
        window.center()
        return window
    }
}
