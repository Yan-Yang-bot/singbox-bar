#!/bin/bash
# SingBoxBar installer: builds a menu-bar app that starts/stops sing-box
# and toggles the macOS SOCKS proxy for a network service (default: Wi-Fi).
# Usage:  bash install-singbox-bar.sh
set -e

# Version comes from git, never hard-coded / 版本号取自 git，不写死:
#   - in-app updates pass the tag via SINGBOXBAR_VERSION / 应用内升级通过 SINGBOXBAR_VERSION 传入标签
#   - otherwise `git describe --tags` (e.g. v1.2.0, or v1.2.0-3-gabc123 for untagged commits)
#   - no tag at all → 0.0.0-dev
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="${SINGBOXBAR_VERSION:-$(git -C "$SRC_DIR" describe --tags 2>/dev/null || echo 0.0.0-dev)}"
VERSION="${VERSION#v}"
APP="$HOME/Applications/SingBoxBar.app"
WORK="$(mktemp -d)"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Apple Command Line Tools are required; an installer window is opening. Run this script again when it finishes."
  echo "需要先安装苹果命令行工具，正在弹出安装窗口；装好后再运行一次本脚本。"
  xcode-select --install || true
  exit 1
fi

cat > "$WORK/main.swift" <<'SWIFT'
import Cocoa

let home = FileManager.default.homeDirectoryForCurrentUser.path
let logPath = home + "/Library/Logs/SingBoxBar.log"
let NS = "/usr/sbin/networksetup"
let defaults = UserDefaults.standard
let appVersion = "__VERSION__"
let repo = "Yan-Yang-bot/singbox-bar"
let updateLog = home + "/Library/Logs/SingBoxBar-update.log"

// MARK: - Language

/// UI language: saved choice, otherwise follow the system's preferred language.
var isZh: Bool {
    get {
        if let v = defaults.string(forKey: "lang") { return v == "zh" }
        return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
    }
    set { defaults.set(newValue ? "zh" : "en", forKey: "lang") }
}
func L(_ zh: String, _ en: String) -> String { isZh ? zh : en }

// MARK: - Helpers

@discardableResult
func sh(_ path: String, _ args: [String]) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

func autodetectBin() -> String {
    let c = ["/opt/homebrew/bin/sing-box", "/usr/local/bin/sing-box",
             home + "/bin/sing-box", home + "/.local/bin/sing-box"]
    return c.first { FileManager.default.isExecutableFile(atPath: $0) } ?? c[0]
}

var binPath: String {
    get { defaults.string(forKey: "bin") ?? autodetectBin() }
    set { defaults.set(newValue, forKey: "bin") }
}
var cfgPath: String {
    get { defaults.string(forKey: "cfg") ?? home + "/.config/sing-box/config.json" }
    set { defaults.set(newValue, forKey: "cfg") }
}
var service: String {
    get { defaults.string(forKey: "svc") ?? "Wi-Fi" }
    set { defaults.set(newValue, forKey: "svc") }
}

func isRunning() -> Bool { sh("/usr/bin/pgrep", ["-x", "sing-box"]).0 == 0 }

func proxyEnabled() -> Bool {
    sh(NS, ["-getsocksfirewallproxy", service]).1.contains("Enabled: Yes")
}

/// Finds the first socks/mixed inbound in the sing-box config.
func socksEndpoint() -> (String, Int)? {
    guard let d = FileManager.default.contents(atPath: cfgPath),
          let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
          let ins = j["inbounds"] as? [[String: Any]] else { return nil }
    for i in ins {
        let t = i["type"] as? String ?? ""
        if t == "socks" || t == "mixed", let port = i["listen_port"] as? Int {
            var host = i["listen"] as? String ?? "127.0.0.1"
            if host.isEmpty || host == "::" || host == "0.0.0.0" { host = "127.0.0.1" }
            return (host, port)
        }
    }
    return nil
}

func networkServices() -> [String] {
    sh(NS, ["-listallnetworkservices"]).1
        .split(separator: "\n").dropFirst().map(String.init)
        .filter { !$0.isEmpty && !$0.hasPrefix("*") }
}

func logTail() -> String {
    let s = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
    return String(s.suffix(800))
}

// MARK: - Updates

/// "v1.2.0" / "1.2.0-3-gabc123" / "0.0.0-dev" → [1,2,0] / [1,2,0] / [0,0,0]
func parseVer(_ s: String) -> [Int] {
    var t = Substring(s)
    if t.first == "v" || t.first == "V" { t = t.dropFirst() }
    let core = t.split(whereSeparator: { $0 == "-" || $0 == "+" }).first ?? ""
    return core.split(separator: ".").map { Int($0) ?? 0 }
}
func isNewer(_ a: String, than b: String) -> Bool {
    let x = parseVer(a), y = parseVer(b)
    for i in 0..<max(x.count, y.count) {
        let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
        if p != q { return p > q }
    }
    return false
}

/// Calls back with (reached GitHub?, highest `v*` tag or nil if none). URLSession honours the system proxy.
func fetchLatestTag(_ done: @escaping (Bool, String?) -> Void) {
    var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/tags?per_page=100")!)
    req.setValue("SingBoxBar", forHTTPHeaderField: "User-Agent")
    req.timeoutInterval = 15
    URLSession.shared.dataTask(with: req) { data, resp, _ in
        var best: String?
        var reached = false
        if let data = data, (resp as? HTTPURLResponse)?.statusCode == 200,
           let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            reached = true
            for t in arr {
                guard let n = t["name"] as? String, n.hasPrefix("v") else { continue }
                if best == nil || isNewer(n, than: best!) { best = n }
            }
        }
        DispatchQueue.main.async { done(reached, best) }
    }.resume()
}

func alert(_ title: String, _ info: String = "") {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.messageText = title
    a.informativeText = info
    a.runModal()
}

// MARK: - App

class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var startItem: NSMenuItem!
    var stopItem: NSMenuItem!
    var binItem: NSMenuItem!
    var cfgItem: NSMenuItem!
    let svcItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var updateItem: NSMenuItem!
    var latestTag: String?
    var updating = false
    var child: Process?

    func applicationDidFinishLaunching(_ n: Notification) {
        menu.autoenablesItems = false
        statusLine.isEnabled = false
        svcItem.submenu = NSMenu()
        item.menu = menu
        buildMenu()
        fetchLatestTag { [weak self] _, t in self?.latestTag = t; self?.refresh() }
        Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(refresh),
                             userInfo: nil, repeats: true)
    }

    /// (Re)creates every menu item in the current language.
    func buildMenu() {
        menu.removeAllItems()
        menu.addItem(statusLine)
        menu.addItem(.separator())
        startItem = add(L("启动 sing-box 并开代理", "Start sing-box & enable proxy"), #selector(start), "s")
        stopItem  = add(L("停止 sing-box 并关代理", "Stop sing-box & disable proxy"), #selector(stop), "x")
        menu.addItem(.separator())
        binItem = add("", #selector(pickBin), "")
        cfgItem = add("", #selector(pickCfg), "")
        menu.addItem(svcItem)
        add(L("查看日志", "Show Log"), #selector(openLog), "l")
        add(L("Switch to English", "切换到中文"), #selector(toggleLanguage), "")
        menu.addItem(.separator())
        updateItem = add("", #selector(checkUpdate), "u")
        menu.addItem(.separator())
        add(L("停止并退出", "Stop & Quit"), #selector(stopAndQuit), "")
        add(L("退出（保持当前状态）", "Quit (keep current state)"), #selector(quit), "q")
        refresh()
    }

    @discardableResult
    func add(_ t: String, _ s: Selector, _ k: String) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: s, keyEquivalent: k)
        i.target = self
        menu.addItem(i)
        return i
    }

    func setTitle(_ mark: String, _ color: NSColor, _ tip: String) {
        let s = NSMutableAttributedString(string: mark,
            attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 13)])
        s.append(NSAttributedString(string: " SB",
            attributes: [.font: NSFont.menuBarFont(ofSize: 0)]))
        item.button?.attributedTitle = s
        item.button?.toolTip = tip
        statusLine.title = tip
    }

    @objc func refresh() {
        let running = isRunning(), proxy = proxyEnabled()
        switch (running, proxy) {
        case (true, true):
            setTitle("●", .systemGreen,
                     L("运行中 · \(service) SOCKS 代理已开", "Running · \(service) SOCKS proxy on"))
        case (true, false):
            setTitle("◐", .systemOrange,
                     L("sing-box 在运行，但系统代理没开", "sing-box running, but system proxy is off"))
        case (false, true):
            setTitle("⚠", .systemRed,
                     L("代理开着但 sing-box 没运行（会断网）", "Proxy on but sing-box not running (no network)"))
        default:
            setTitle("○", .secondaryLabelColor, L("已停止", "Stopped"))
        }
        startItem.isEnabled = !(running && proxy)
        stopItem.isEnabled = running || proxy
        binItem.title = L("程序：", "Binary: ") + binPath
        cfgItem.title = L("配置：", "Config: ") + cfgPath
        svcItem.title = L("网络服务：", "Network service: ") + service
        if updating {
            updateItem.title = L("正在升级，完成后自动重启…（当前 v\(appVersion)）", "Updating, will restart when done… (current v\(appVersion))")
            updateItem.isEnabled = false
        } else if let t = latestTag, isNewer(t, than: appVersion) {
            updateItem.title = L("⬆ 升级到 \(t)…（当前 v\(appVersion)）", "⬆ Update to \(t)… (current v\(appVersion))")
            updateItem.isEnabled = true
        } else {
            updateItem.title = L("检查更新…（当前 v\(appVersion)）", "Check for Updates… (current v\(appVersion))")
            updateItem.isEnabled = true
        }
        let sub = svcItem.submenu!
        sub.removeAllItems()
        for s in networkServices() {
            let i = NSMenuItem(title: s, action: #selector(pickService(_:)), keyEquivalent: "")
            i.target = self
            i.state = (s == service) ? .on : .off
            sub.addItem(i)
        }
    }

    @objc func start() {
        guard let (host, port) = socksEndpoint() else {
            alert(L("配置里找不到 socks 或 mixed 入站", "No socks or mixed inbound found in config"),
                  L("请确认配置文件路径正确，且 inbounds 里有 type 为 socks/mixed、带 listen_port 的条目。",
                    "Make sure the config path is correct and `inbounds` contains an entry of type socks/mixed with a listen_port.")
                  + "\n\n\(cfgPath)")
            return
        }
        if !isRunning() {
            guard FileManager.default.isExecutableFile(atPath: binPath) else {
                alert(L("找不到 sing-box 程序", "sing-box binary not found"),
                      binPath + "\n\n" + L("请在菜单里点“程序：”重新选择。",
                                           "Click “Binary:” in the menu to choose it."))
                return
            }
            FileManager.default.createFile(atPath: logPath, contents: nil)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: binPath)
            p.arguments = ["run", "-c", cfgPath]
            p.currentDirectoryURL = URL(fileURLWithPath: (cfgPath as NSString).deletingLastPathComponent)
            if let fh = FileHandle(forWritingAtPath: logPath) {
                p.standardOutput = fh; p.standardError = fh
            }
            do { try p.run() } catch {
                alert(L("启动失败", "Failed to start"), "\(error)"); return
            }
            child = p
            Thread.sleep(forTimeInterval: 1.0)
            if !p.isRunning {
                alert(L("sing-box 启动后马上退出了", "sing-box exited right after starting"), logTail())
                refresh(); return
            }
        }
        let r1 = sh(NS, ["-setsocksfirewallproxy", service, host, String(port)])
        let r2 = sh(NS, ["-setsocksfirewallproxystate", service, "on"])
        if r1.0 != 0 || r2.0 != 0 {
            alert(L("设置系统代理失败", "Failed to set system proxy"), r1.1 + r2.1)
        }
        refresh()
    }

    @objc func stop() {
        // Disable the proxy first so it never points at a dead port.
        // 先关代理，避免代理指向一个已经不存在的端口。
        sh(NS, ["-setsocksfirewallproxystate", service, "off"])
        child?.terminate(); child = nil
        sh("/usr/bin/pkill", ["-x", "sing-box"])
        for _ in 0..<20 where isRunning() { Thread.sleep(forTimeInterval: 0.1) }
        if isRunning() { sh("/usr/bin/pkill", ["-9", "-x", "sing-box"]) }
        refresh()
    }

    func choose(_ start: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = false
        p.showsHiddenFiles = true
        p.directoryURL = URL(fileURLWithPath: (start as NSString).deletingLastPathComponent)
        return p.runModal() == .OK ? p.url?.path : nil
    }
    @objc func pickBin() { if let s = choose(binPath) { binPath = s; refresh() } }
    @objc func pickCfg() { if let s = choose(cfgPath) { cfgPath = s; refresh() } }
    @objc func pickService(_ i: NSMenuItem) {
        if proxyEnabled() { sh(NS, ["-setsocksfirewallproxystate", service, "off"]) }
        service = i.title; refresh()
    }
    @objc func toggleLanguage() { isZh.toggle(); buildMenu() }

    @objc func checkUpdate() {
        fetchLatestTag { [weak self] reached, tag in
            guard let self = self else { return }
            if let tag = tag { self.latestTag = tag }
            self.refresh()
            guard reached else {
                alert(L("检查更新失败", "Update check failed"),
                      L("无法连接 GitHub，请检查网络后重试。",
                        "Could not reach GitHub. Check your network and try again."))
                return
            }
            guard let t = tag else {
                alert(L("GitHub 上还没有发布任何版本", "No releases on GitHub yet"),
                      L("仓库里还没有 v 开头的版本标签。", "The repository has no v* version tags yet."))
                return
            }
            guard isNewer(t, than: appVersion) else {
                alert(L("已是最新版本", "You're up to date"), "v\(appVersion)")
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = L("发现新版本 \(t)", "New version \(t) available")
            a.informativeText = L(
                "当前版本 v\(appVersion)。升级会从 GitHub 下载源码并在本机重新编译安装，约需一分钟，完成后 App 自动重启。sing-box 和系统代理的状态不受影响。",
                "Current version: v\(appVersion). The update downloads the source from GitHub and rebuilds the app locally (about a minute), then restarts it. sing-box and the system proxy are not affected.")
            a.addButton(withTitle: L("立即升级", "Update Now"))
            a.addButton(withTitle: L("取消", "Cancel"))
            if a.runModal() == .alertFirstButtonReturn { self.performUpdate(t) }
        }
    }

    /// Downloads the tag's source tarball and runs its installer detached;
    /// the installer quits this app, rebuilds it and relaunches the new version.
    func performUpdate(_ tag: String) {
        updating = true
        refresh()
        let url = URL(string: "https://codeload.github.com/\(repo)/tar.gz/refs/tags/\(tag)")!
        URLSession.shared.downloadTask(with: url) { tmp, resp, err in
            let dir = NSTemporaryDirectory() + "singboxbar-update-" + UUID().uuidString
            var ok = false
            if let tmp = tmp, (resp as? HTTPURLResponse)?.statusCode == 200 {
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                ok = (try? FileManager.default.moveItem(atPath: tmp.path, toPath: dir + "/src.tgz")) != nil
            }
            DispatchQueue.main.async {
                guard ok else {
                    self.updating = false
                    self.refresh()
                    alert(L("下载失败", "Download failed"), err?.localizedDescription ?? "")
                    return
                }
                let script = """
                #!/bin/bash
                set -e
                cd "\(dir)"
                tar -xzf src.tgz
                S="$(find . -maxdepth 2 -name install-singbox-bar.sh | head -1)"
                SINGBOXBAR_VERSION="\(tag)" bash "$S"
                """
                try? script.write(toFile: dir + "/update.sh", atomically: true, encoding: .utf8)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/bash")
                p.arguments = ["-c", "nohup /bin/bash '\(dir)/update.sh' > '\(updateLog)' 2>&1 &"]
                do { try p.run() } catch {
                    self.updating = false
                    self.refresh()
                    alert(L("升级失败", "Update failed"), "\(error)")
                }
            }
        }.resume()
    }
    @objc func openLog() {
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }
    @objc func stopAndQuit() { stop(); NSApp.terminate(nil) }
    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
SWIFT
sed -i '' "s|__VERSION__|$VERSION|" "$WORK/main.swift"
SHORT_VERSION="${VERSION%%-*}"

pkill -x SingBoxBar 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
echo "Compiling… / 正在编译…"
xcrun swiftc -O "$WORK/main.swift" -o "$APP/Contents/MacOS/SingBoxBar"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SingBoxBar</string>
  <key>CFBundleIdentifier</key><string>local.singboxbar</string>
  <key>CFBundleExecutable</key><string>SingBoxBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>$SHORT_VERSION</string>
  <key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
</dict>
</plist>
PLIST

codesign --force -s - "$APP" >/dev/null 2>&1 || true
rm -rf "$WORK"
open "$APP"
echo "Installed v$VERSION / 已安装 v$VERSION: $APP"
echo "Look for the “● SB / ○ SB” icon in the menu bar. / 右上角会出现“● SB / ○ SB”图标。"
echo "Launch at login: System Settings → General → Login Items → add SingBoxBar."
echo "开机自动运行：系统设置 → 通用 → 登录项 → 添加 SingBoxBar。"
