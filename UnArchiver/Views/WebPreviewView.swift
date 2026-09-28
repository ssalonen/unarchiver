import SwiftUI
import WebKit

@MainActor
struct WebPreviewView: View {
    let document: WebPreviewDocument
    @State private var error: String?

    var body: some View {
        if let error {
            ContentUnavailableView("Cannot Preview", systemImage: "exclamationmark.triangle",
                                   description: Text(error))
        } else {
            RestrictedWebView(document: document) { error = $0.localizedDescription }
        }
    }
}

/// Defense in depth: no page JavaScript, an ephemeral data store, a restrictive
/// CSP, a content blocker installed BEFORE loading, and no follow-up navigation.
@MainActor
struct RestrictedWebView: UIViewRepresentable {
    let document: WebPreviewDocument
    let onError: (Error) -> Void

    static let blockingRules = """
    [
      {"trigger":{"url-filter":".*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"^unarchiver-preview:"},"action":{"type":"ignore-previous-rules"}},
      {"trigger":{"url-filter":"^data:image/","resource-type":["image"]},"action":{"type":"ignore-previous-rules"}}
    ]
    """

    func makeCoordinator() -> Coordinator { Coordinator(document: document, onError: onError) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = Self.makeWebView(coordinator: context.coordinator)
        context.coordinator.load(webView)
        return webView
    }

    static func makeWebView(coordinator: Coordinator,
                            configuration config: WKWebViewConfiguration = WKWebViewConfiguration()) -> WKWebView {
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.dataDetectorTypes = []
        config.setURLSchemeHandler(coordinator, forURLScheme: WebPreviewDocument.scheme)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.allowsLinkPreview = false
        webView.accessibilityIdentifier = "webDocumentPreview"
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.cancel()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKURLSchemeHandler, WKNavigationDelegate, WKUIDelegate {
        let document: WebPreviewDocument
        private let onError: (Error) -> Void
        private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
        private var lastTask: Task<Void, Never>?
        private var cancelled = false
        private var awaitingInitialNavigation = true

        init(document: WebPreviewDocument, onError: @escaping (Error) -> Void) {
            self.document = document
            self.onError = onError
        }

        func load(_ webView: WKWebView) {
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "UnArchiverOfflinePreview-v1", encodedContentRuleList: RestrictedWebView.blockingRules
            ) { [weak self, weak webView] rules, error in
                Task { @MainActor in
                    guard let self, let webView, !self.cancelled else { return }
                    guard let rules else {
                        // Fail closed: never render without the network blocker.
                        self.onError(error ?? WebPreviewDocument.PreviewError.unavailable)
                        return
                    }
                    webView.configuration.userContentController.add(rules)
                    webView.load(URLRequest(url: self.document.url))
                }
            }
        }

        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            let id = ObjectIdentifier(urlSchemeTask)
            guard !cancelled, tasks.count <= WebPreviewDocument.maxImageCount,
                  urlSchemeTask.request.httpMethod == "GET", let url = urlSchemeTask.request.url else {
                urlSchemeTask.didFailWithError(WebPreviewDocument.PreviewError.unavailable)
                return
            }
            // Serialize extraction so a page with many images cannot inflate
            // several copies of a compressed archive at the same time.
            let previous = lastTask
            tasks[id] = Task { @MainActor [weak self] in
                await previous?.value
                guard let self, !Task.isCancelled, !self.cancelled else { return }
                defer { self.tasks.removeValue(forKey: id) }
                do {
                    let resource = try await self.document.resource(at: url)
                    guard !Task.isCancelled, !self.cancelled else { return }
                    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                        "Content-Type": resource.mimeType + (resource.mimeType == "text/html" ? "; charset=utf-8" : ""),
                        "Content-Security-Policy": WebPreviewDocument.contentSecurityPolicy + "; sandbox",
                        "X-Content-Type-Options": "nosniff",
                        "X-DNS-Prefetch-Control": "off",
                        "Cache-Control": "no-store",
                        "Referrer-Policy": "no-referrer"
                    ])!
                    urlSchemeTask.didReceive(response)
                    urlSchemeTask.didReceive(resource.data)
                    urlSchemeTask.didFinish()
                } catch {
                    guard !Task.isCancelled, !self.cancelled else { return }
                    urlSchemeTask.didFailWithError(error)
                }
            }
            lastTask = tasks[id]
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
            tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
        }

        func cancel() {
            cancelled = true
            tasks.values.forEach { $0.cancel() }
            tasks.removeAll()
            lastTask = nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let initial = awaitingInitialNavigation && navigationAction.targetFrame?.isMainFrame == true
                && navigationAction.navigationType == .other && navigationAction.request.url == document.url
            if initial { awaitingInitialNavigation = false }
            // Includes links, forms, refresh redirects, file://, custom schemes,
            // downloads, subframes and target=_blank. Nothing opens another app.
            decisionHandler(initial ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { onError(error) }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            onError(WebPreviewDocument.PreviewError.unavailable)
        }
    }
}
