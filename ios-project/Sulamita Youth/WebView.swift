import UIKit
import WebKit
import AuthenticationServices
import SafariServices


func createWebView(container: UIView, WKSMH: WKScriptMessageHandler, WKND: WKNavigationDelegate, NSO: NSObject, VC: ViewController) -> WKWebView{

    let config = WKWebViewConfiguration()
    let userContentController = WKUserContentController()

    userContentController.add(WKSMH, name: "print")
    // F7 (option A): the four push-* handlers are not registered. Nothing on the
    // site ever posts to them, and handleSubscribeTouch / handleFCMToken reach
    // Messaging.messaging() while FirebaseApp.configure() is commented out in
    // AppDelegate — a live handler was a crash waiting for a caller. Push stays
    // on the web platform (Home Screen install from Safari), which pwa-install.js
    // already handles. PushNotifications.swift is left in the target untouched.

    config.userContentController = userContentController

    config.limitsNavigationsToAppBoundDomains = true;
    config.allowsInlineMediaPlayback = true
    // F11: the iOS default is .all, which left Instagram reels and stories parked
    // on their poster frame — insta-circles.js calls video.play() and swallows the
    // rejection, and the story auto-advance has no gesture at all. The site's video
    // is inline, muted, poster-backed and controls-first.
    config.mediaTypesRequiringUserActionForPlayback = []
    config.preferences.javaScriptCanOpenWindowsAutomatically = true
    config.preferences.setValue(true, forKey: "standalone")
    
    let webView = WKWebView(frame: calcWebviewFrame(webviewView: container, toolbarView: nil), configuration: config)
    
    setCustomCookie(webView: webView)

    webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

    webView.isHidden = true;

    webView.navigationDelegate = WKND

    webView.scrollView.bounces = false
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    webView.allowsBackForwardNavigationGestures = true
    
    let deviceModel = UIDevice.current.model
    let osVersion = UIDevice.current.systemVersion
    webView.configuration.applicationNameForUserAgent = "Safari/604.1"
    webView.customUserAgent = "Mozilla/5.0 (\(deviceModel); CPU \(deviceModel) OS \(osVersion.replacingOccurrences(of: ".", with: "_")) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(osVersion) Mobile/15E148 Safari/604.1 SulamitaYouth"

    webView.addObserver(NSO, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: NSKeyValueObservingOptions.new, context: nil)
    
    #if DEBUG
    if #available(iOS 16.4, *) {
        webView.isInspectable = true
    }
    #endif
    
    return webView
}

func setAppStoreAsReferrer(contentController: WKUserContentController) {
    let scriptSource = "document.referrer = `app-info://platform/ios-store`;"
    let script = WKUserScript(source: scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    contentController.addUserScript(script);
}

func setCustomCookie(webView: WKWebView) {
    let _platformCookie = HTTPCookie(properties: [
        .domain: rootUrl.host!,
        .path: "/",
        .name: platformCookie.name,
        .value: platformCookie.value,
        .secure: "FALSE",
        .expires: NSDate(timeIntervalSinceNow: 31556926)
    ])!

    webView.configuration.websiteDataStore.httpCookieStore.setCookie(_platformCookie)

}

func calcWebviewFrame(webviewView: UIView, toolbarView: UIToolbar?) -> CGRect{
    if ((toolbarView) != nil) {
        return CGRect(x: 0, y: toolbarView!.frame.height, width: webviewView.frame.width, height: webviewView.frame.height - toolbarView!.frame.height)
    }
    else {
        let winScene = UIApplication.shared.connectedScenes.first
        let windowScene = winScene as! UIWindowScene
        var statusBarHeight = windowScene.statusBarManager?.statusBarFrame.height ?? 0

        switch displayMode {
        case "fullscreen":
            #if targetEnvironment(macCatalyst)
                if let titlebar = windowScene.titlebar {
                    titlebar.titleVisibility = .hidden
                    titlebar.toolbar = nil
                }
            #endif
            return CGRect(x: 0, y: 0, width: webviewView.frame.width, height: webviewView.frame.height)
        default:
            #if targetEnvironment(macCatalyst)
            statusBarHeight = 29
            #endif
            let windowHeight = webviewView.frame.height - statusBarHeight
            return CGRect(x: 0, y: statusBarHeight, width: webviewView.frame.width, height: windowHeight)
        }
    }
}

extension ViewController: WKUIDelegate, WKDownloadDelegate {
    // window.open() gets a REAL popup web view, presented as a sheet the buyer can close.
    // Google Pay and Cash App Pay run their authorisation in a popup that must share
    // the opener's configuration (so it can talk back to the page). The template used
    // to load the popup URL into the main view, which then hit the host filter below
    // and ended on a Safari sheet with no opener — Daniel saw that as an error page.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.uiDelegate = self
        popup.allowsBackForwardNavigationGestures = true
        let host = UIViewController()
        host.view.backgroundColor = .systemBackground
        popup.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(popup)
        NSLayoutConstraint.activate([
            popup.topAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.topAnchor),
            popup.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
            popup.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: host.view.trailingAnchor)
        ])
        host.modalPresentationStyle = .pageSheet
        self.present(host, animated: true, completion: nil)
        return popup
    }
    // window.close() from inside the popup dismisses the sheet.
    func webViewDidClose(_ webView: WKWebView) {
        if let presented = self.presentedViewController, webView.isDescendant(of: presented.view) {
            presented.dismiss(animated: true, completion: nil)
        }
    }
    // restrict navigation to target host, open external links in 3rd party apps
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if (navigationAction.request.url?.scheme == "about") {
            return decisionHandler(.allow)
        }
        if (navigationAction.shouldPerformDownload) {
            return decisionHandler(.download)
        }
        // F4: a blob: URL asking for a NEW window (yf-files.js / yf-transactions.js do
        // `window.open(URL.createObjectURL(blob))`) must reach createWebViewWith and
        // become a popup sheet. Only a same-frame blob navigation is a download.
        if (navigationAction.request.url?.scheme == "blob") {
            return decisionHandler(navigationAction.targetFrame == nil ? .allow : .download)
        }

        // Sub-frame loads (Square's Web Payments SDK draws its card fields and wallet
        // buttons in iframes on web.squarecdn.com / pci-connect.squareup.com) stay inside
        // the web view. Without this, every iframe load off our host was cancelled and
        // presented as a Safari sheet, which Daniel saw on /give as a jump to a Square site.
        if let frame = navigationAction.targetFrame, !frame.isMainFrame {
            return decisionHandler(.allow)
        }

        if let requestUrl = navigationAction.request.url{
            if let requestHost = requestUrl.host {
                // NOTE: Match auth origin first, because host origin may be a subset of auth origin and may therefore always match
                let matchingAuthOrigin = authOrigins.first(where: { requestHost.caseInsensitiveCompare($0) == .orderedSame })
                if (matchingAuthOrigin != nil) {
                    decisionHandler(.allow)
                    if (toolbarView.isHidden) {
                        toolbarView.isHidden = false
                        webView.frame = calcWebviewFrame(webviewView: webviewView, toolbarView: toolbarView)
                    }
                    return
                }

                let matchingHostOrigin = allowedOrigins.first(where: { requestHost.caseInsensitiveCompare($0) == .orderedSame })
                if (matchingHostOrigin != nil) {
                    // Open in main webview
                    decisionHandler(.allow)
                    if (!toolbarView.isHidden) {
                        toolbarView.isHidden = true
                        webView.frame = calcWebviewFrame(webviewView: webviewView, toolbarView: nil)
                    }
                    return
                }
                decisionHandler(.cancel)


                if ["http", "https"].contains(requestUrl.scheme?.lowercased() ?? "") {
                    // Can open with SFSafariViewController
                    let safariViewController = SFSafariViewController(url: requestUrl)
                    self.present(safariViewController, animated: true, completion: nil)
                } else {
                    // F10: canOpenURL returns false for every scheme absent from
                    // LSApplicationQueriesSchemes, which silently swallowed the
                    // viber:// invites the YF portal hands out. open() needs no
                    // declaration — ask the system and report what it answers.
                    UIApplication.shared.open(requestUrl, options: [:]) { opened in
                        if (!opened) { print("F10: no installed app can open \(requestUrl)") }
                    }
                }
            } else {
                decisionHandler(.cancel)
                // F10: hostless URLs. The scheme test used to name only tel and mailto,
                // so the first sms:/maps:/itms-apps: link added to the site would have
                // been swallowed. Hand every non-http scheme to the system.
                if requestUrl.isFileURL {
                    // not tested
                    downloadAndOpenFile(url: requestUrl.absoluteURL)
                }
                else if (!["http", "https"].contains(requestUrl.scheme?.lowercased() ?? "")) {
                    UIApplication.shared.open(requestUrl, options: [:]) { opened in
                        if (!opened) { print("F10: no installed app can open \(requestUrl)") }
                    }
                }
                // if (requestUrl.absoluteString.contains("base64")){
                //     downloadAndOpenBase64File(base64String: requestUrl.absoluteString)
                // }
            }
        }
        else {
            decisionHandler(.cancel)
        }

    }
    // F5: a server-set `Content-Disposition: attachment` (the calendar's /feed.ics,
    // the ?dl=1 photo routes, YF exports) is decided here, not in the action delegate
    // — shouldPerformDownload is false for an ordinary link. With no response delegate
    // WKWebView defaulted to .allow and tried to render text/calendar as a page, so the
    // visitor got a blank white screen. Needs F3's downloadDidFinish to be useful.
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if (!navigationResponse.canShowMIMEType) {
            return decisionHandler(.download)
        }
        if let http = navigationResponse.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().hasPrefix("attachment") {
            return decisionHandler(.download)
        }
        decisionHandler(.allow)
    }

    // Handle javascript: `window.alert(message: String)`
    func webView(_ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void) {

        // Set the message as the UIAlertController message
        let alert = UIAlertController(
            title: nil,
            message: message,
            preferredStyle: .alert
        )

        // Add a confirmation action “OK”
        let okAction = UIAlertAction(
            title: "OK",
            style: .default,
            handler: { _ in
                // Call completionHandler
                completionHandler()
            }
        )
        alert.addAction(okAction)

        // Display the NSAlert
        present(alert, animated: true, completion: nil)
    }
    // Handle javascript: `window.confirm(message: String)`
    func webView(_ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void) {

        // Set the message as the UIAlertController message
        let alert = UIAlertController(
            title: nil,
            message: message,
            preferredStyle: .alert
        )

        // Add a confirmation action “Cancel”
        let cancelAction = UIAlertAction(
            title: "Cancel",
            style: .cancel,
            handler: { _ in
                // Call completionHandler
                completionHandler(false)
            }
        )

        // Add a confirmation action “OK”
        let okAction = UIAlertAction(
            title: "OK",
            style: .default,
            handler: { _ in
                // Call completionHandler
                completionHandler(true)
            }
        )
        alert.addAction(cancelAction)
        alert.addAction(okAction)

        // Display the NSAlert
        present(alert, animated: true, completion: nil)
    }
    // Handle javascript: `window.prompt(prompt: String, defaultText: String?)`
    func webView(_ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void) {

        // Set the message as the UIAlertController message
        let alert = UIAlertController(
            title: nil,
            message: prompt,
            preferredStyle: .alert
        )

        // Add a confirmation action “Cancel”
        let cancelAction = UIAlertAction(
            title: "Cancel",
            style: .cancel,
            handler: { _ in
                // Call completionHandler
                completionHandler(nil)
            }
        )

        // Add a confirmation action “OK”
        let okAction = UIAlertAction(
            title: "OK",
            style: .default,
            handler: { _ in
                // Call completionHandler with Alert input
                if let input = alert.textFields?.first?.text {
                    completionHandler(input)
                }
            }
        )

        alert.addTextField { textField in
            textField.placeholder = defaultText
        }
        alert.addAction(cancelAction)
        alert.addAction(okAction)

        // Display the NSAlert
        present(alert, animated: true, completion: nil)
    }

    func downloadAndOpenFile(url: URL){

        let destinationFileUrl = url
        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig)
        let request = URLRequest(url:url)
        let task = session.downloadTask(with: request) { (tempLocalUrl, response, error) in
            if let tempLocalUrl = tempLocalUrl, error == nil {
                if let statusCode = (response as? HTTPURLResponse)?.statusCode {
                    print("Successfully download. Status code: \(statusCode)")
                }
                do {
                    try FileManager.default.copyItem(at: tempLocalUrl, to: destinationFileUrl)
                    self.openFile(url: destinationFileUrl)
                } catch (let writeError) {
                    print("Error creating a file \(destinationFileUrl) : \(writeError)")
                }
            } else {
                print("Error took place while downloading a file. Error description: \(error?.localizedDescription ?? "N/A") ")
            }
        }
        task.resume()
    }

    // func downloadAndOpenBase64File(base64String: String) {
    //     // Split the base64 string to extract the data and the file extension
    //     let components = base64String.components(separatedBy: ";base64,")

    //     // Make sure the base64 string has the correct format
    //     guard components.count == 2, let format = components.first?.split(separator: "/").last else {
    //         print("Invalid base64 string format")
    //         return
    //     }

    //     // Remove the data type prefix to get the base64 data
    //     let dataString = components.last!

    //     if let imageData = Data(base64Encoded: dataString) {
    //         let documentsUrl: URL  =  FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    //         let destinationFileUrl = documentsUrl.appendingPathComponent("image.\(format)")

    //         do {
    //             try imageData.write(to: destinationFileUrl)
    //             self.openFile(url: destinationFileUrl)
    //         } catch {
    //             print("Error writing image to file url: \(destinationFileUrl): \(error)")
    //         }
    //     }
    // }

    func openFile(url: URL) {
        self.documentController = UIDocumentInteractionController(url: url)
        self.documentController?.delegate = self
        self.documentController?.presentPreview(animated: true)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    // F3: openFile() used to run HERE, before completionHandler handed WebKit the
    // destination — it previewed a path that had just been deleted and not yet written,
    // which is why every photo Save, Daily Word card, album share card and YF export
    // opened an empty preview. Remember the destination and present it on finish.
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                suggestedFilename: String,
                completionHandler: @escaping (URL?) -> Void) {

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(suggestedFilename)

        // Remove existing file if it exists, otherwise it may show an old file/content just by having the same name.
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }

        self.pendingDownloadURL = fileURL
        completionHandler(fileURL)
    }

    // F3: the file exists only once WebKit says it is done.
    func downloadDidFinish(_ download: WKDownload) {
        guard let fileURL = self.pendingDownloadURL else { return }
        self.pendingDownloadURL = nil
        DispatchQueue.main.async {
            self.openFile(url: fileURL)
        }
    }

    // F3: there was no failure path at all — a failed save looked identical to a
    // successful one that showed nothing.
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        self.pendingDownloadURL = nil
        let message = error.localizedDescription
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "Download failed", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }
}
