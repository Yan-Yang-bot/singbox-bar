# SingBoxBar

A tiny macOS menu-bar app that starts/stops [sing-box](https://github.com/SagerNet/sing-box) and toggles the system SOCKS proxy in one click — so you always know whether sing-box is running.

一个 macOS 菜单栏小工具：一键启动/停止 sing-box，同时开关系统 SOCKS 代理，右上角随时显示运行状态。

## 安装

```bash
git clone https://github.com/Yan-Yang-bot/singbox-bar.git
cd singbox-bar
bash install-singbox-bar.sh
```

需要苹果命令行工具（脚本会提示 `xcode-select --install`）。App 安装到 `~/Applications/SingBoxBar.app`。
想开机自动运行：系统设置 → 通用 → 登录项 → 添加 SingBoxBar。

## 图标含义

| 图标 | 状态 |
|---|---|
| 🟢 `● SB` | sing-box 运行中，系统 SOCKS 代理已开 |
| 🟠 `◐ SB` | sing-box 在后台运行，但系统代理没开 |
| 🔴 `⚠ SB` | 代理开着但 sing-box 没运行（会断网） |
| ⚪ `○ SB` | 已停止 |

## 功能

- **启动**：运行 `sing-box run -c <config>`，并把所选网络服务（默认 Wi-Fi）的 SOCKS 代理指向配置中第一个 `socks` / `mixed` 入站的端口。
- **停止**：先关系统代理，再结束所有 `sing-box` 进程（包括不是本工具启动的）。
- 菜单中可重新选择 sing-box 程序路径、配置文件和网络服务。
- 日志：`~/Library/Logs/SingBoxBar.log`

默认路径：程序自动查找 Homebrew 等常见位置，配置为 `~/.config/sing-box/config.json`。

## 限制

- 只处理 socks / mixed 入站 + 系统 SOCKS 代理；TUN 模式需要 root，不在本工具范围内。

## 许可 / License

[PolyForm Noncommercial 1.0.0](LICENSE.md)：可自由使用、修改、分享，但**禁止任何形式的商业用途**。
Free to use, modify and share for noncommercial purposes only; any commercial use is prohibited.
