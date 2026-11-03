// 位置シミュレータ — server.py を裏で起動し、その画面を WKWebView で表示する Mac アプリ。
import Cocoa
import WebKit

let serverURL = URL(string: "http://127.0.0.1:8765")!
let tunneldURL = URL(string: "http://127.0.0.1:49151")!
let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("LocSim")
let venvDir = supportDir.appendingPathComponent("venv")

final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var server: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.uiDelegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "位置シミュレータ"
        window.contentView = webView
        window.setFrameAutosaveName("main")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.global().async { self.boot() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        // SIGINT で終了させると server.py がシミュレーションを解除してから終わる
        guard let server, server.isRunning else { return }
        server.interrupt()
        let deadline = Date().addingTimeInterval(8)
        while server.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if server.isRunning { server.terminate() }
    }

    // MARK: - 起動処理

    func boot() {
        do {
            try ensureVenv()
            try ensureTunneld()
            try startServer()
            DispatchQueue.main.async { self.webView.load(URLRequest(url: serverURL)) }
        } catch {
            showMessage("起動に失敗しました", detail: error.localizedDescription, isError: true)
        }
    }

    func ensureVenv() throws {
        let pmd = venvDir.appendingPathComponent("bin/pymobiledevice3").path
        if FileManager.default.isExecutableFile(atPath: pmd) { return }
        showMessage("初回セットアップ中…", detail: "pymobiledevice3 をインストールしています（数分かかります）")
        let python = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let python else { throw AppError("python3 が見つかりません。Homebrew などでインストールしてください") }
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try run(python, ["-m", "venv", venvDir.path])
        try run(venvDir.appendingPathComponent("bin/pip").path, ["install", "-q", "pymobiledevice3"])
    }

    func ensureTunneld() throws {
        if isReachable(tunneldURL) { return }
        showMessage("tunneld を起動します…", detail: "iOS 17 以降の端末と通信するため、管理者パスワードが必要です")
        let pmd = venvDir.appendingPathComponent("bin/pymobiledevice3").path
        let shell = "'\(pmd)' remote tunneld > /dev/null 2>&1 &"
        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: "do shell script \"\(shell)\" with administrator privileges")!
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw AppError("tunneld を起動できませんでした: \(errorInfo[NSAppleScript.errorMessage] ?? "")")
        }
        guard waitUntil(reachable: tunneldURL, seconds: 20) else { throw AppError("tunneld が応答しません") }
    }

    func startServer() throws {
        if isReachable(serverURL) { return }  // 既に起動している場合はそれを使う
        guard let script = Bundle.main.url(forResource: "server", withExtension: "py") else {
            throw AppError("server.py がアプリ内に見つかりません")
        }
        let p = Process()
        p.executableURL = venvDir.appendingPathComponent("bin/python")
        p.arguments = [script.path, "--no-browser"]
        p.currentDirectoryURL = script.deletingLastPathComponent()
        try p.run()
        server = p
        guard waitUntil(reachable: serverURL, seconds: 15) else { throw AppError("サーバーが起動しませんでした") }
    }

    // MARK: - ヘルパー

    func run(_ path: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let errPipe = Pipe()
        p.standardError = errPipe
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw AppError("\(URL(fileURLWithPath: path).lastPathComponent) が失敗しました\n\(msg)")
        }
    }

    func isReachable(_ url: URL) -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            ok = response != nil
            sem.signal()
        }.resume()
        sem.wait()
        return ok
    }

    func waitUntil(reachable url: URL, seconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if isReachable(url) { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    func showMessage(_ title: String, detail: String, isError: Bool = false) {
        let esc = { (s: String) in
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        }
        let html = """
        <html><body style="font:14px -apple-system,sans-serif;display:flex;flex-direction:column;align-items:center;
        justify-content:center;height:100vh;margin:0;color:#555;background:#f6f6f4">
        <style>@media(prefers-color-scheme:dark){body{background:#161617!important;color:#bbb!important}}</style>
        <h2 style="color:\(isError ? "#c2410c" : "inherit")">\(esc(title))</h2>
        <pre style="white-space:pre-wrap;max-width:600px">\(esc(detail))</pre></body></html>
        """
        DispatchQueue.main.async { self.webView.loadHTMLString(html, baseURL: nil) }
    }

    func setupMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "位置シミュレータを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "編集")
        editMenu.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "表示")
        viewMenu.addItem(withTitle: "再読み込み", action: #selector(reload), keyEquivalent: "r")
        viewItem.submenu = viewMenu
        main.addItem(viewItem)
        NSApp.mainMenu = main
    }

    @objc func reload() { webView.reload() }

    // MARK: - WKUIDelegate（prompt と GPX のファイル選択に必要）

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "キャンセル")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) }
    }
}

struct AppError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
