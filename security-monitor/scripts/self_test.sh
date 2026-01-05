#!/usr/bin/env bash
# ------------------------------------------------------------
# self_test.sh
#
# Basic post-install checks.
# ------------------------------------------------------------

set -euo pipefail

PASS=0
FAIL=0

ok() { echo "✅ $1"; PASS=$((PASS+1)); }
no() { echo "❌ $1"; echo "   $2"; FAIL=$((FAIL+1)); }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "请用 root 权限运行: sudo $0" >&2
    exit 1
  fi
}

check_service() {
  local name="$1"
  if systemctl is-active --quiet "$name"; then
    ok "服务运行: $name"
  else
    no "服务运行: $name" "当前未运行，可尝试: systemctl start $name"
  fi
}

main() {
  require_root
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║        🔍 Web安全监控系统 - 功能自检                      ║"
  echo "╚════════════════════════════════════════════════════════════╝"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "1) Web面板与 Apache"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if systemctl is-active --quiet apache2; then
    ok "Apache服务状态"
  else
    no "Apache服务状态" "Apache未运行"
  fi

  if [[ -f "/var/www/html/security_dashboard.php" ]]; then
    ok "监控面板文件"
  else
    no "监控面板文件" "/var/www/html/security_dashboard.php 不存在"
  fi

  http_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/security_dashboard.php || true)
  if [[ "$http_code" == "200" || "$http_code" == "403" ]]; then
    ok "HTTP响应" 
  else
    no "HTTP响应" "HTTP $http_code（可能还未部署或 Apache 配置异常）"
  fi

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "2) systemd 服务"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  check_service traffic-monitor
  check_service internal-monitor

  if systemctl is-active --quiet security-monitor-collector.timer; then
    ok "collector.timer 运行"
  else
    no "collector.timer 运行" "可尝试: systemctl start security-monitor-collector.timer"
  fi

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "3) 日志与快照"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  for f in \
    /var/log/security_monitor/traffic_monitor.log \
    /var/log/security_monitor/internal_monitor.log \
    /var/log/security_monitor/dashboard_system.txt \
    /var/log/security_monitor/dashboard_meta.txt
  do
    if [[ -f "$f" ]]; then
      ok "存在: $f"
    else
      no "存在: $f" "文件不存在（可能 collector 尚未运行或权限问题）"
    fi
  done

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "4) Snort / Fail2ban（可选）"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if systemctl list-unit-files | grep -q '^snort\.service'; then
    if systemctl is-active --quiet snort; then
      ok "Snort服务状态"
    else
      no "Snort服务状态" "Snort未运行"
    fi
  else
    echo "ℹ️  未检测到 snort.service（不同发行版可能不同）"
  fi

  if systemctl list-unit-files | grep -q '^fail2ban\.service'; then
    if systemctl is-active --quiet fail2ban; then
      ok "Fail2ban服务状态"
    else
      no "Fail2ban服务状态" "Fail2ban未运行"
    fi
  else
    echo "ℹ️  未检测到 fail2ban.service"
  fi

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "结果汇总"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "通过: $PASS  失败: $FAIL"

  if (( FAIL > 0 )); then
    exit 1
  fi
}

main
