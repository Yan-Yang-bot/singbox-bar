#!/bin/bash
# SingBoxBar installer: builds a menu-bar app that starts/stops sing-box
# and toggles the macOS SOCKS proxy for a network service (default: Wi-Fi).
# Usage:  bash install-singbox-bar.sh
set -e

APP="$HOME/Applications/SingBoxBar.app"
WORK="$(mktemp -d)"

if ! xcrun --find swiftc >/dev/null 2>&1; then
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

func alert(_ title: String, _ info: String = "") {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.messageText = title
    a.informativeText = info
    a.runModal()
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var startItem: NSMenuItem!
    var stopItem: NSMenuItem!
    let binItem = NSMenuItem(title: "", action: #selector(pickBin), keyEquivalent: "")
    let cfgItem = NSMenuItem(title: "", action: #selector(pickCfg), keyEquivalent: "")
    let svcItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var child: Process?

    func applicationDidFinishLaunching(_ n: Notification) {
        menu.autoenablesItems = false
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        startItem = add("启动 sing-box 并开代理", #selector(start), "s")
        stopItem = add("停止 sing-box 并关代理", #selector(stop), "x")
        menu.addItem(.separator())
        for i in [binItem, cfgItem] { i.target = self; menu.addItem(i) }
        svcItem.submenu = NSMenu()
        menu.addItem(svcItem)
        add("查看日志", #selector(openLog), "l")
        menu.addItem(.separator())
        add("停止并退出", #selector(stopAndQuit), "")
        add("退出（保持当前状态）", #selector(quit), "q")
        item.menu = menu
        refresh()
        Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(refresh),
                             userInfo: nil, repeats: true)
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
        case (true, true):  setTitle("●", .systemGreen,  "运行中 · \(service) SOCKS 代理已开")
        case (true, false): setTitle("◐", .systemOrange, "sing-box 在运行，但系统代理没开")
        case (false, true): setTitle("⚠", .systemRed,    "代理开着但 sing-box 没运行（会断网）")
        default:            setTitle("○", .secondaryLabelColor, "已停止")
        }
        startItem.isEnabled = !(running && proxy)
        stopItem.isEnabled = running || proxy
        binItem.title = "程序：\(binPath)"
        cfgItem.title = "配置：\(cfgPath)"
        svcItem.title = "网络服务：\(service)"
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
            alert("配置里找不到 socks 或 mixed 入站",
                  "请确认配置文件路径正确，且 inbounds 里有 type 为 socks/mixed、带 listen_port 的条目。\n\n\(cfgPath)")
            return
        }
        if !isRunning() {
            guard FileManager.default.isExecutableFile(atPath: binPath) else {
                alert("找不到 sing-box 程序", binPath + "\n\n请在菜单里点“程序：”重新选择。"); return
            }
            FileManager.default.createFile(atPath: logPath, contents: nil)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: binPath)
            p.arguments = ["run", "-c", cfgPath]
            p.currentDirectoryURL = URL(fileURLWithPath: (cfgPath as NSString).deletingLastPathComponent)
            if let fh = FileHandle(forWritingAtPath: logPath) {
                p.standardOutput = fh; p.standardError = fh
            }
            do { try p.run() } catch { alert("启动失败", "\(error)"); return }
            child = p
            Thread.sleep(forTimeInterval: 1.0)
            if !p.isRunning {
                alert("sing-box 启动后马上退出了", logTail()); refresh(); return
            }
        }
        let r1 = sh(NS, ["-setsocksfirewallproxy", service, host, String(port)])
        let r2 = sh(NS, ["-setsocksfirewallproxystate", service, "on"])
        if r1.0 != 0 || r2.0 != 0 { alert("设置系统代理失败", r1.1 + r2.1) }
        refresh()
    }

    @objc func stop() {
        // 先关代理，避免代理指向一个已经不存在的端口
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

pkill -x SingBoxBar 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
echo "正在编译…"
xcrun swiftc -O "$WORK/main.swift" -o "$APP/Contents/MacOS/SingBoxBar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SingBoxBar</string>
  <key>CFBundleIdentifier</key><string>local.singboxbar</string>
  <key>CFBundleExecutable</key><string>SingBoxBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
</dict>
</plist>
PLIST

codesign --force -s - "$APP" >/dev/null 2>&1 || true
rm -rf "$WORK"
open "$APP"
echo "装好了：$APP"
echo "右上角会出现“● SB / ○ SB”图标。想开机自动运行：系统设置 → 通用 → 登录项 → 添加 SingBoxBar。"
