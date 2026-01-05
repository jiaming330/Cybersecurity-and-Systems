#!/usr/bin/env bash
# Install systemd units from the repo and start services.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "错误: 请使用 root 权限运行此脚本" >&2
  echo "用法: sudo $0" >&2
  exit 1
fi

echo "安装 systemd 单元文件..."
install -m 0644 "$ROOT_DIR/systemd/traffic-monitor.service" /etc/systemd/system/traffic-monitor.service
install -m 0644 "$ROOT_DIR/systemd/internal-monitor.service" /etc/systemd/system/internal-monitor.service
install -m 0644 "$ROOT_DIR/systemd/security-monitor-collector.service" /etc/systemd/system/security-monitor-collector.service
install -m 0644 "$ROOT_DIR/systemd/security-monitor-collector.timer" /etc/systemd/system/security-monitor-collector.timer

systemctl daemon-reload

echo "启用并启动服务..."
systemctl enable traffic-monitor internal-monitor security-monitor-collector.timer
systemctl restart traffic-monitor internal-monitor
systemctl start security-monitor-collector.timer

echo "完成。"
echo "查看状态: systemctl status traffic-monitor internal-monitor security-monitor-collector.timer"
