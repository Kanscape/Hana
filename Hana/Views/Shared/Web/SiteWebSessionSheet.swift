import SwiftUI
import WebKit

struct SiteWebSessionSheet: View {
    let flow: SiteWebFlow
    let onComplete: ([HTTPCookie]) -> Void
    let onCancel: () -> Void

    @State private var cookies: [HTTPCookie] = []

    var body: some View {
        NavigationStack {
            SiteWebView(
                flow: flow,
                onCookiesChanged: { cookies in
                    self.cookies = cookies
                },
                onFlowCompleted: { cookies in
                    onComplete(cookies)
                }
            )
            .navigationTitle(flow.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "取消", systemImage: "xmark", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    HanaToolbarIconButton(title: "完成", systemImage: "checkmark") {
                        onComplete(cookies)
                    }
                }
            }
        }
    }
}

#if os(iOS) || os(visionOS)
struct SiteWebView: UIViewRepresentable {
    let flow: SiteWebFlow
    let onCookiesChanged: ([HTTPCookie]) -> Void
    let onFlowCompleted: ([HTTPCookie]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            flow: flow,
            onCookiesChanged: onCookiesChanged,
            onFlowCompleted: onFlowCompleted
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = HanaHTTPClient.userAgent
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: flow.url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
#elseif os(macOS)
struct SiteWebView: NSViewRepresentable {
    let flow: SiteWebFlow
    let onCookiesChanged: ([HTTPCookie]) -> Void
    let onFlowCompleted: ([HTTPCookie]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            flow: flow,
            onCookiesChanged: onCookiesChanged,
            onFlowCompleted: onFlowCompleted
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = HanaHTTPClient.userAgent
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: flow.url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
#endif

extension SiteWebView {
    final class Coordinator: NSObject, WKNavigationDelegate {
        let flow: SiteWebFlow
        let onCookiesChanged: ([HTTPCookie]) -> Void
        let onFlowCompleted: ([HTTPCookie]) -> Void
        private var hasCompletedLogin = false
        private var hasCompletedCloudflare = false
        private var isCloudflareCheckScheduled = false
        private var cloudflareCheckAttempts = 0

        init(
            flow: SiteWebFlow,
            onCookiesChanged: @escaping ([HTTPCookie]) -> Void,
            onFlowCompleted: @escaping ([HTTPCookie]) -> Void
        ) {
            self.flow = flow
            self.onCookiesChanged = onCookiesChanged
            self.onFlowCompleted = onFlowCompleted
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            syncCookies(from: webView)
            scheduleCloudflareCompletionCheck(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if shouldCompleteLogin(for: navigationAction) {
                completeLogin(from: webView)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if shouldCompleteLogin(for: navigationResponse) {
                completeLogin(from: webView)
            }
            decisionHandler(.allow)
        }

        private func shouldCompleteLogin(for navigationAction: WKNavigationAction) -> Bool {
            guard flow.kind == .login,
                  !hasCompletedLogin,
                  navigationAction.targetFrame?.isMainFrame == true,
                  let url = navigationAction.request.url,
                  isSameSite(url),
                  !isLoginURL(url) else {
                return false
            }
            return true
        }

        private func shouldCompleteLogin(for navigationResponse: WKNavigationResponse) -> Bool {
            guard flow.kind == .login,
                  !hasCompletedLogin,
                  navigationResponse.isForMainFrame,
                  let response = navigationResponse.response as? HTTPURLResponse,
                  let url = response.url,
                  isSameSite(url) else {
                return false
            }
            return response.statusCode == 404 && isLoginURL(url)
        }

        private func completeLogin(from webView: WKWebView) {
            hasCompletedLogin = true
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [onFlowCompleted] cookies in
                onFlowCompleted(cookies)
            }
        }

        private func syncCookies(from webView: WKWebView) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [onCookiesChanged] cookies in
                onCookiesChanged(cookies)
            }
        }

        private func scheduleCloudflareCompletionCheck(from webView: WKWebView) {
            guard flow.kind == .cloudflare,
                  !hasCompletedCloudflare,
                  !isCloudflareCheckScheduled,
                  cloudflareCheckAttempts < 60 else {
                return
            }

            isCloudflareCheckScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.isCloudflareCheckScheduled = false
                self.cloudflareCheckAttempts += 1
                self.completeCloudflareIfReady(from: webView)
            }
        }

        private func completeCloudflareIfReady(from webView: WKWebView) {
            webView.evaluateJavaScript("document.head ? document.head.innerHTML : ''") { [weak self, weak webView] result, _ in
                guard let self, let webView, !self.hasCompletedCloudflare else { return }
                let html = result as? String ?? ""
                guard !self.containsCloudflareChallengeMarker(html) else {
                    self.scheduleCloudflareCompletionCheck(from: webView)
                    return
                }

                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self, weak webView] cookies in
                    guard let self, let webView, !self.hasCompletedCloudflare else { return }
                    guard self.cookiesForFlowHost(cookies).contains(where: { $0.name == "cf_clearance" }) else {
                        self.scheduleCloudflareCompletionCheck(from: webView)
                        return
                    }

                    self.hasCompletedCloudflare = true
                    self.onCookiesChanged(cookies)
                    self.onFlowCompleted(cookies)
                }
            }
        }

        private func containsCloudflareChallengeMarker(_ html: String) -> Bool {
            [
                "#challenge-form",
                "challenge-form",
                "#challenge-success-text",
                "challenge-success-text",
                "#challenge-error-text",
                "challenge-error-text"
            ].contains { html.localizedCaseInsensitiveContains($0) }
        }

        private func cookiesForFlowHost(_ cookies: [HTTPCookie]) -> [HTTPCookie] {
            guard let host = flow.url.host() else { return cookies }
            return cookies.filter { cookie in
                let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return domain == host || domain.contains(host) || host.contains(domain)
            }
        }

        private func isLoginURL(_ url: URL) -> Bool {
            url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "login"
        }

        private func isSameSite(_ url: URL) -> Bool {
            guard let flowHost = flow.url.host(), let urlHost = url.host() else {
                return false
            }
            return flowHost == urlHost
        }
    }
}
