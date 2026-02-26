import SwiftUI
import WebKit

/// A window that shows claude.ai login in a WKWebView.
/// Once the user logs in, we grab the sessionKey cookie from the WebView's cookie store.
/// Zero permissions needed — the WebView has its own cookie jar.

// MARK: - Login Window Controller

class LoginWindowController: NSObject {
    private var window: NSWindow?
    private var onSessionKey: ((String) -> Void)?

    func show(onSessionKey: @escaping (String) -> Void) {
        self.onSessionKey = onSessionKey

        let webView = LoginWebViewController(onSessionKey: { [weak self] key in
            onSessionKey(key)
            self?.window?.close()
            self?.window = nil
        })

        let hostingView = NSHostingView(rootView: LoginWebViewWrapper(controller: webView))

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Sign in to Claude"
        win.contentView = hostingView
        win.center()
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
    }
}

// MARK: - WebView Wrapper

struct LoginWebViewWrapper: NSViewRepresentable {
    let controller: LoginWebViewController

    func makeNSView(context: Context) -> WKWebView {
        return controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - WebView Controller

class LoginWebViewController: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private var onSessionKey: ((String) -> Void)?
    private var cookieCheckTimer: Timer?

    init(onSessionKey: @escaping (String) -> Void) {
        self.onSessionKey = onSessionKey

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        // Inject script to mask WebView detection before any page JS runs
        let antiDetectScript = WKUserScript(
            source: """
            // Override properties that sites use to detect embedded WebViews
            Object.defineProperty(navigator, 'standalone', { get: () => false });
            Object.defineProperty(navigator, 'webdriver', { get: () => false });
            // Ensure window.safari exists (real Safari has this)
            if (!window.safari) {
                window.safari = { pushNotification: { permission: () => 'default', requestPermission: () => {} } };
            }
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(antiDetectScript)

        self.webView = WKWebView(frame: .zero, configuration: config)

        super.init()

        webView.navigationDelegate = self

        // Use a realistic, current Safari user agent
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"

        // Allow dev tools inspection for debugging
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        // Load claude.ai login
        if let url = URL(string: "https://claude.ai/login") {
            webView.load(URLRequest(url: url))
        }

        // Start polling for the sessionKey cookie
        startCookiePolling()
    }

    deinit {
        cookieCheckTimer?.invalidate()
    }

    // MARK: - Cookie Polling

    /// Poll the WebView's cookie store every 2 seconds looking for sessionKey
    private func startCookiePolling() {
        cookieCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkForSessionKey()
        }
    }

    private func checkForSessionKey() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            for cookie in cookies {
                if cookie.domain.contains("claude.ai") && cookie.name == "sessionKey" && !cookie.value.isEmpty {
                    DispatchQueue.main.async {
                        self?.cookieCheckTimer?.invalidate()
                        self?.cookieCheckTimer = nil
                        self?.onSessionKey?(cookie.value)
                        self?.onSessionKey = nil
                    }
                    return
                }
            }
        }
    }

    // MARK: - Navigation Delegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Also check after each page load
        checkForSessionKey()
    }
}
