# SingBoxBar

A tiny macOS menu-bar app that starts/stops [sing-box](https://github.com/SagerNet/sing-box) and toggles the system SOCKS proxy in one click — so you always know whether sing-box is running.

一个 macOS 菜单栏小工具：一键启动/停止 [sing-box](https://github.com/SagerNet/sing-box)，同时开关系统 SOCKS 代理，右上角随时显示运行状态。

## Installation / 安装

```bash
git clone https://github.com/Yan-Yang-bot/singbox-bar.git
cd singbox-bar
bash install-singbox-bar.sh
```

Requires Apple Command Line Tools (the script will prompt `xcode-select --install` if missing). The app is installed to `~/Applications/SingBoxBar.app`.

需要苹果命令行工具（如未安装，脚本会提示运行 `xcode-select --install`）。App 安装到 `~/Applications/SingBoxBar.app`。

To launch at login: System Settings → General → Login Items → add SingBoxBar.

开机自动运行：系统设置 → 通用 → 登录项 → 添加 SingBoxBar。

## Updating / 升级

From v1.2.0 on, click **Check for Updates…** in the menu. If a newer version is tagged on GitHub, the app downloads it, rebuilds itself locally (about a minute) and restarts. sing-box and the system proxy are not affected.

从 v1.2.0 起，点菜单里的 **检查更新…**。如果 GitHub 上有更新的版本号，App 会自动下载、在本机重新编译安装（约一分钟）并重启。sing-box 和系统代理的状态不受影响。

Older versions: run `git pull && bash install-singbox-bar.sh` in the repo folder (the installer replaces the old app).

更早的版本：在仓库目录里运行 `git pull && bash install-singbox-bar.sh`（安装脚本会自动替换旧版本）。

## Uninstalling / 卸载

```bash
bash uninstall.sh
```

Removes the app, its settings and logs. sing-box itself, its config and the current system proxy setting are left untouched.

删除 App、它的设置和日志。不会动 sing-box 本身、它的配置文件，以及当前的系统代理设置。

## Releasing (maintainers) / 发布新版本（维护者）

Just tag a commit: `git tag vX.Y.Z && git push --tags` (or create a Release on GitHub). The version is taken from the tag — nothing is hard-coded. Installing from an untagged commit shows e.g. `v1.2.0-3-gabc123`; with no tags at all, `v0.0.0-dev`.

只需给提交打标签：`git tag vX.Y.Z && git push --tags`（或在 GitHub 上建 Release）。版本号直接取自标签，不写死在代码里。从未打标签的提交安装会显示类似 `v1.2.0-3-gabc123`；仓库完全没有标签时显示 `v0.0.0-dev`。

## Menu-bar icon / 图标含义

| Icon / 图标 | Status | 状态 |
|---|---|---|
| 🟢 `● SB` | sing-box running, system SOCKS proxy on | sing-box 运行中，系统 SOCKS 代理已开 |
| 🟠 `◐ SB` | sing-box running in background, system proxy off | sing-box 在后台运行，但系统代理没开 |
| 🔴 `⚠ SB` | Proxy on but sing-box not running (no network) | 代理开着但 sing-box 没运行（会断网） |
| ⚪ `○ SB` | Stopped | 已停止 |

## Features / 功能

- **Start**: runs `sing-box run -c <config>` and points the SOCKS proxy of the selected network service (default: Wi-Fi) at the first `socks` / `mixed` inbound in the config.
  **启动**：运行 `sing-box run -c <config>`，并把所选网络服务（默认 Wi-Fi）的 SOCKS 代理指向配置中第一个 `socks` / `mixed` 入站的端口。
- **Stop**: turns off the system proxy first, then terminates all `sing-box` processes (including ones not started by this app).
  **停止**：先关系统代理，再结束所有 `sing-box` 进程（包括不是本工具启动的）。
- The sing-box binary path, config file and network service can all be changed from the menu.
  菜单中可重新选择 sing-box 程序路径、配置文件和网络服务。
- Menu option to toggle the UI between English and Chinese. Initial language: Chinese if the macOS language is Simplified or Traditional Chinese, English otherwise. Your choice is remembered.
  菜单中可一键切换中英文界面。初始语言：macOS 系统语言为简体或繁体中文时用中文，其余一律用英文。切换后会记住你的选择。
- Log file: `~/Library/Logs/SingBoxBar.log`
  日志文件：`~/Library/Logs/SingBoxBar.log`

Defaults: the binary is auto-detected in common locations (Homebrew, etc.); the config defaults to `~/.config/sing-box/config.json`.

默认路径：程序自动在 Homebrew 等常见位置查找；配置文件默认为 `~/.config/sing-box/config.json`。

## Limitations / 限制

- Only handles `socks` / `mixed` inbounds with the system SOCKS proxy. TUN mode requires root and is out of scope.
  只处理 `socks` / `mixed` 入站 + 系统 SOCKS 代理；TUN 模式需要 root 权限，不在本工具范围内。

## License / 许可

[PolyForm Noncommercial 1.0.0](LICENSE.md): free to use, modify and share for noncommercial purposes only; **any commercial use is prohibited**.

[PolyForm Noncommercial 1.0.0](LICENSE.md)：可自由使用、修改、分享，但**禁止任何形式的商业用途**。
