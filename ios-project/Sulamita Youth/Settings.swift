import WebKit

struct Cookie {
    var name: String
    var value: String
}

// URL for first launch
let rootUrl = URL(string: "https://youth.sulamitachurch.com")!

// allowed origin is for what we are sticking to pwa domain
// This should also appear in Info.plist
// F1 (Cash App Pay redirect) + F2 (merch store door): a main-frame navigation to
// any host not listed here is cancelled and re-presented in an SFSafariViewController
// with its own cookie jar, so Cash App's return redirect never reaches the give page
// and "See the shop" leaves the app. Sandbox host deliberately omitted.
// Every entry here must also appear in Info.plist's WKAppBoundDomains.
let allowedOrigins: [String] = [
    "youth.sulamitachurch.com",
    "merch.sulamitachurch.com",
    "cash.app",
]

// auth origins will open in modal and show toolbar for back into the main origin.
// These should also appear in Info.plist
let authOrigins: [String] = []
// allowedOrigins + authOrigins <= 10

let platformCookie = Cookie(name: "app-platform", value: "iOS App Store")

// UI options
let displayMode = "fullscreen" // standalone / fullscreen. fullscreen (2026-08-27): the site is safe-area aware (viewport-fit=cover + env() padding), so the web view runs edge to edge like its Safari home-screen install; standalone left a blank band under the status bar.
let adaptiveUIStyle = true     // iOS 15+ only. Change app theme on the fly to dark/light related to WebView background color.
let overrideStatusBar = false   // iOS 13-14 only. if you don't support dark/light system theme.
let statusBarTheme = "dark"    // dark / light, related to override option.
// F6: off. An over-scroll reloaded the page and silently destroyed the join
// selfie (join.js holds the frame in a page-local variable) and dropped the YF
// SPA back to its root; the site is network-first through its own service
// worker and never asks for a reload button.
let pullToRefresh = false    // Enable/disable pull down to refresh page
