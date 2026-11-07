#!/bin/bash
# Uninstall SingBoxBar / 卸载 SingBoxBar
# sing-box itself, its config and the current system proxy setting are left untouched.
# 不会动 sing-box 本身、它的配置文件，以及当前的系统代理设置。

pkill -x SingBoxBar 2>/dev/null || true
rm -rf "$HOME/Applications/SingBoxBar.app"
defaults delete local.singboxbar 2>/dev/null || true
rm -f "$HOME/Library/Logs/SingBoxBar.log" "$HOME/Library/Logs/SingBoxBar-update.log"

echo "SingBoxBar removed. / SingBoxBar 已卸载。"
echo "If you added it to Login Items, remove it there too: System Settings → General → Login Items."
echo "如果加过登录项，请到 系统设置 → 通用 → 登录项 里一并移除。"
