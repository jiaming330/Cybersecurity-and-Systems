#!/usr/bin/env bash
# Minimal deploy helper (without installing dependencies).
# For full installation, prefer: sudo ./scripts/install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "错误: 请使用 root 权限运行" >&2
  echo "使用方法: sudo $0" >&2
  exit 1
fi

echo "正在部署脚本..."
install -m 0755 "$ROOT_DIR/scripts/traffic_monitor.sh" /usr/local/bin/traffic_monitor.sh
install -m 0755 "$ROOT_DIR/scripts/internal_monitor.sh" /usr/local/bin/internal_monitor.sh
install -m 0755 "$ROOT_DIR/scripts/collect_dashboard_data.sh" /usr/local/bin/collect_dashboard_data.sh

mkdir -p /var/log/security_monitor
:> /var/log/security_monitor/traffic_monitor.log
:> /var/log/security_monitor/traffic_alerts.log
:> /var/log/security_monitor/internal_monitor.log
:> /var/log/security_monitor/internal_alerts.log
chmod 0644 /var/log/security_monitor/*.log || true

echo "✅ 已部署到 /usr/local/bin (traffic_monitor.sh / internal_monitor.sh / collect_dashboard_data.sh)"
echo "✅ 日志目录: /var/log/security_monitor/"

echo "\n脚本自检:"
/usr/local/bin/traffic_monitor.sh help | head -20 || true
/usr/local/bin/internal_monitor.sh help | head -20 || true

echo "\n下一步（可选）: sudo ./scripts/setup_services.sh 以安装 systemd 服务" 
