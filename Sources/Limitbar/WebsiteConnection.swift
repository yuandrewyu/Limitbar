import AppKit
import SwiftUI
import WebKit
import LimitbarCore

@MainActor
final class WebsiteConnection: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let service: WebsiteService
    let webView: WKWebView
    @Published private(set) var address = ""
    @Published var status = "Sign in on the website, open Usage, then choose Read usage & connect."
    @Published private(set) var reading = false
    private var window: NSWindow?
    private var navigationError: String?

    init(service: WebsiteService) {
        self.service = service
        let configuration = WKWebViewConfiguration()
        // This persistent WebKit session belongs to Limitbar; Safari/Chrome cookies are not imported.
        configuration.websiteDataStore = service == .codex ? .default() : WKWebsiteDataStore(forIdentifier: UUID(uuidString: "3DF40BD1-6780-462B-938B-F394F92455A8")!)
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func show(store: UsageStore) {
        if window == nil {
            let view = WebsiteConnectionView(store: store, connection: self)
            let controller = NSHostingController(rootView: view)
            let browserWindow = NSWindow(contentViewController: controller)
            browserWindow.title = "\(service.name) website — Prototype"
            browserWindow.setContentSize(NSSize(width: 1000, height: 740))
            browserWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            browserWindow.isReleasedWhenClosed = false
            browserWindow.center()
            window = browserWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if webView.url == nil { loadUsagePage() }
    }

    func loadUsagePage() {
        navigationError = nil
        webView.load(URLRequest(url: service.usageURL))
    }

    func read(reload: Bool) async throws -> UsageSnapshot {
        guard !reading else { throw ConnectionError.message("A website reading is already in progress.") }
        reading = true
        defer { reading = false }
        navigationError = nil
        if reload, service == .claude, let url = webView.url, service.isUsageURL(url) {
            webView.reload()
        } else if reload || webView.url == nil { loadUsagePage() }
        // The site is a SPA: navigation completion does not mean the quota cards have rendered.
        let deadline = Date().addingTimeInterval(20)
        repeat {
            try Task.checkCancellation()
            if let navigationError { throw ConnectionError.message(navigationError) }
            if !webView.isLoading, let url = webView.url,
               service.isUsageURL(url) {
                do {
                    if let json = try await webView.evaluateJavaScript(service.extractionScript) as? String {
                        return try service.decode(Data(json.utf8))
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { /* Wait for the usage cards to finish rendering. */ }
            }
            try await Task.sleep(for: .milliseconds(500))
        } while Date() < deadline
        if webView.isLoading {
            throw ConnectionError.message("The usage page is still loading. Wait for the limits to appear, then try again.")
        }
        if let url = webView.url, !service.isUsageURL(url) {
            throw ConnectionError.message("The browser is not on a supported usage page. Finish signing in, then click Usage page and try again.")
        }
        throw ConnectionError.message("No clearly labeled \(service.name) usage was found. Open the English usage page and try again. The website layout may be unsupported.")
    }

    func clearSession() async {
        webView.stopLoading()
        await webView.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        status = "Website session cleared. Sign in again to reconnect."
        loadUsagePage()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        address = webView.url?.absoluteString ?? ""
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        address = webView.url?.absoluteString ?? ""
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        navigationError = "The website could not load: \(error.localizedDescription)"
        status = navigationError!
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, url.scheme == "https" || url.absoluteString == "about:blank" else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // Keep sign-in popup navigation inside this same WebKit session.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil,
           navigationAction.request.url?.scheme == "https" {
            webView.load(navigationAction.request)
        }
        return nil
    }

    private enum ConnectionError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let value): return value }
        }
    }


}

private struct WebsiteBrowser: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct WebsiteConnectionView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var connection: WebsiteConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(connection.service.name) website · Prototype").font(.headline)
                Spacer()
                Button("Usage page") { connection.loadUsagePage() }
                    .disabled(connection.reading)
                Button("Read usage & connect") { Task { await store.connectWebsite(connection.service) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(connection.reading || !store.loadedSafely || store.refreshing)
            }
            Text("Sign in below. This session stays in Limitbar on this Mac. Your regular browser login is separate.")
                .font(.callout)
            Text(connection.address.isEmpty ? "Loading \(connection.service.usageURL.host ?? "website")…" : connection.address)
                .font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
            HStack {
                if connection.reading { ProgressView().controlSize(.small) }
                Text(connection.status).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            WebsiteBrowser(webView: connection.webView)
            Text("After connection, usage refreshes every minute while Limitbar runs, even with this window closed. Sign in again only if your session expires. Reset times inferred from website text are approximate.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(minWidth: 760, minHeight: 560)
    }
}
