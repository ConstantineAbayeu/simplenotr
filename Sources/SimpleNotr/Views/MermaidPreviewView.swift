import SwiftUI
import WebKit

struct MermaidPreviewView: NSViewRepresentable {
    let content: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        context.coordinator.lastContent = content
        webView.loadHTMLString(buildHTML(content: content), baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastContent != content else { return }
        context.coordinator.lastContent = content

        if context.coordinator.isLoaded {
            updateDiagram(webView, content: content)
        } else {
            // Page hasn't finished loading yet — reload with new content
            webView.loadHTMLString(buildHTML(content: content), baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var isLoaded = false
        var lastContent: String = ""

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
        }

        // Block link-click navigations; allow the initial HTML load and CDN sub-resources.
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.navigationType == .other ? .allow : .cancel)
        }
    }

    // MARK: - JS injection for live updates (avoids re-fetching the CDN)

    private func updateDiagram(_ webView: WKWebView, content: String) {
        guard let json = jsonEncode(content) else { return }
        webView.evaluateJavaScript("renderDiagram(\(json));", completionHandler: nil)
    }

    // MARK: - HTML template

    private func buildHTML(content: String) -> String {
        let json = jsonEncode(content) ?? "\"\""
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                html, body { margin: 0; padding: 0; }
                body {
                    padding: 20px;
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    background: #ffffff;
                }
                @media (prefers-color-scheme: dark) {
                    body { background: #1e1e1e; }
                }
                #diagram { display: flex; justify-content: center; }
            </style>
        </head>
        <body>
            <div id="diagram"></div>
            <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
            <script>
                const dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
                mermaid.initialize({
                    startOnLoad: false,
                    theme: dark ? 'dark' : 'default',
                    securityLevel: 'strict'
                });
                function renderDiagram(src) {
                    const el = document.getElementById('diagram');
                    el.removeAttribute('data-processed');
                    el.innerHTML = '';
                    el.textContent = src;
                    mermaid.init(undefined, el);
                }
                renderDiagram(\(json));
            </script>
        </body>
        </html>
        """
    }

    private func jsonEncode(_ s: String) -> String? {
        (try? JSONEncoder().encode(s)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
