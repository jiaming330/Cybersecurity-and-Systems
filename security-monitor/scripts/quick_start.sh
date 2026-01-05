#!/usr/bin/env bash
# Quick start helper for the repo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "❌ 错误: 请使用 root 权限运行" >&2
  echo "用法: sudo $0" >&2
  exit 1
fi

cat <<GUIDE
╔════════════════════════════════════════════════════════════╗
║        🚀 快速开始 - Web安全监控系统                      ║
╚════════════════════════════════════════════════════════════╝

1) 一键安装（推荐）:
   sudo ./scripts/install.sh

2) （可选）启用防火墙规则（高风险，建议先在虚拟机测试）:
   sudo ./scripts/install.sh --with-firewall

3) 安装完成后访问面板:
   http://<你的IP>/security_dashboard.php

4) 查看服务状态:
   systemctl status traffic-monitor
   systemctl status internal-monitor
   systemctl status security-monitor-collector.timer

5) 查看日志:
   tail -f /var/log/security_monitor/traffic_monitor.log
   tail -f /var/log/security_monitor/internal_monitor.log
   tail -f /var/log/security_monitor/dashboard_system.txt

GUIDE

echo "现在开始执行安装? (y/n)"
read -r -p "> " choice
if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
  "$ROOT_DIR/scripts/install.sh"
else
  echo "已取消。"
fi
