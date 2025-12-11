public typealias DebuggerCallback = (Bool) -> Void

#if os(iOS)

import UIKit
import WebKit

public class StatsigDebugViewController: UIViewController, WKNavigationDelegate,
    WKScriptMessageHandler
{
    private let messageHandlerName = "statsigDebugMessageHandler"

    private var webView: WKWebView?
    private var url: URL
    private var state: [String: Any?]
    private var isReloadRequested: Bool = false
    private var callback: DebuggerCallback?

    static func show(_ sdkKey: String, _ state: [String: Any?], _ callback: DebuggerCallback? = nil)
    {
        guard
            let debugger = StatsigDebugViewController(
                sdkKey: sdkKey, state: state, callback: callback)
        else {
            return
        }

        var root: UIViewController?

        #if !STATSIG_WIDGET_BUILD

        if root == nil, #available(iOS 13.0, *) {
            let scene = UIApplication.shared.connectedScenes.first(where: { scene in
                return scene.activationState == UIScene.ActivationState.foregroundActive
            })

            root = (scene?.delegate as? UIWindowSceneDelegate)?.window??.rootViewController
        }

        if root == nil {
            root = UIApplication.shared.keyWindow?.rootViewController
        }

        #endif

        guard let root = root else {
            PrintHandler.log("[Statsig] DebugView failed to find parent view controller")
            return
        }

        root.present(debugger, animated: true)
    }

    internal init?(sdkKey: String, state: [String: Any?], callback: DebuggerCallback? = nil) {
        guard JSONSerialization.isValidJSONObject(state) else {
            PrintHandler.log("[Statsig] DebugView received Invalid state")
            return nil
        }

        guard
            let url = URL(
                string: "https://console.statsig.com/client_sdk_debugger_redirect?sdkKey=\(sdkKey)")
        else {
            PrintHandler.log("[Statsig] DebugView failed to create required URL")
            return nil
        }

        self.url = url
        self.state = state
        self.callback = callback
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        do {
            let data = try JSONSerialization.data(withJSONObject: self.state, options: [])
            let json = data.text ?? "{}"

            let config = WKWebViewConfiguration()
            let userContentController = WKUserContentController()

            let script = WKUserScript(
                source: "window.__StatsigClientState = \(json)",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false)
            userContentController.addUserScript(script)

            config.userContentController = userContentController

            let webView = WKWebView(frame: view.bounds, configuration: config)
            webView.frame = view.bounds
            webView.navigationDelegate = self
            webView.configuration.userContentController.add(self, name: messageHandlerName)
            view.addSubview(webView)
            webView.load(URLRequest(url: url))
            self.webView = webView
        } catch {
            PrintHandler.log("[Statsig] Failed to create debug state")
        }

        // Add a close button to dismiss the modal view
        let closeButton = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(closeButtonTapped))
        navigationItem.rightBarButtonItem = closeButton

    }

    override public func viewWillDisappear(_ animated: Bool) {
        callback?(isReloadRequested)
    }

    @objc func closeButtonTapped() {
        dismiss(animated: true, completion: nil)
    }

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if message.name != messageHandlerName {
            return
        }

        if message.body as? String == "RELOAD_REQUIRED" {
            isReloadRequested = true
        }
    }

}

#else
public class StatsigDebugViewController {
    static func show(_ sdkKey: String, _ state: [String: Any?], _ callback: DebuggerCallback? = nil)
    {
        PrintHandler.log("[Statsig] DebugView is currently only available on iOS")
    }

    internal init?(sdkKey: String, state: [String: Any?], callback: DebuggerCallback? = nil) {
        return nil
    }
}
#endif
