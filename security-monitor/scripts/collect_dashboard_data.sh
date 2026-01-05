#!/usr/bin/env bash
# ------------------------------------------------------------
# collect_dashboard_data.sh
#
# Collects dashboard-friendly snapshots (as text files) so the
# PHP dashboard can run WITHOUT sudo / shell_exec.
#
# Output (default):
#   /var/log/security_monitor/dashboard_system.txt
#   /var/log/security_monitor/dashboard_network.txt
#   /var/log/security_monitor/dashboard_firewall.txt
#   /var/log/security_monitor/dashboard_snort.txt
#   /var/log/security_monitor/dashboard_syslog.txt
#   /var/log/security_monitor/dashboard_meta.txt
# ------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load config (best-effort)
for f in "/etc/security_monitor/security_monitor.conf" "$SCRIPT_DIR/../config/security_monitor.conf"; do
  if [[ -f "$f" ]]; then
    # shellcheck disable=SC1090
    source "$f"
    break
  fi
done

: "${LOG_DIR:=/var/log/security_monitor}"
mkdir -p "$LOG_DIR"

write_atomically() {
  local path="$1"
  local tmp
  tmp="${path}.tmp"
  cat > "$tmp"
  chmod 0644 "$tmp" || true
  mv -f "$tmp" "$path"
}

iface=$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')
iface=${iface:-eth0}

# System status
{
  echo "系统时间: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "运行时间: $(uptime -p 2>/dev/null || true)"
  echo "负载情况: $(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | xargs || true)"
  # CPU usage (approx)
  cpu_idle=$(top -bn1 2>/dev/null | awk -F',' '/Cpu\(s\)/{for(i=1;i<=NF;i++){if($i~/%id/){gsub(/[^0-9.]/,"",$i); print $i; exit}}}')
  if [[ -n "${cpu_idle:-}" ]]; then
    cpu_used=$(awk -v idle="$cpu_idle" 'BEGIN{printf "%.1f%%", 100-idle}')
    echo "CPU使用率: $cpu_used"
  fi
  mem_used=$(free -h 2>/dev/null | awk '/Mem:/{printf "%.1f%%", $3/$2*100}')
  [[ -n "${mem_used:-}" ]] && echo "内存使用: $mem_used"
  disk_used=$(df -h / 2>/dev/null | awk 'NR==2{print $5}')
  [[ -n "${disk_used:-}" ]] && echo "磁盘使用(/): $disk_used"
} | write_atomically "$LOG_DIR/dashboard_system.txt"

# Network snapshot
{
  established=$(netstat -ant 2>/dev/null | awk '$6=="ESTABLISHED"{c++} END{print c+0}')
  echo "已建立连接: ${established}"
  echo ""
  echo "监听端口(Top 10):"
  ss -tuln 2>/dev/null | head -11 || true
  echo ""
  echo "Top远端IP(Top 5):"
  netstat -ant 2>/dev/null | awk '{print $5}' | cut -d':' -f1 | grep -E '^[0-9]' | sort | uniq -c | sort -rn | head -5 || true
  echo ""
  echo "接口($iface)收发字节(累计):"
  [[ -r "/sys/class/net/$iface/statistics/rx_bytes" ]] && echo "rx_bytes=$(cat /sys/class/net/$iface/statistics/rx_bytes)"
  [[ -r "/sys/class/net/$iface/statistics/tx_bytes" ]] && echo "tx_bytes=$(cat /sys/class/net/$iface/statistics/tx_bytes)"
} | write_atomically "$LOG_DIR/dashboard_network.txt"

# Firewall snapshot (best-effort)
{
  if command -v iptables >/dev/null 2>&1; then
    echo "INPUT链规则(Top 15):"
    iptables -L INPUT -n -v 2>/dev/null | head -15 || true
  else
    echo "iptables not found"
  fi
} | write_atomically "$LOG_DIR/dashboard_firewall.txt"

# Snort alerts (tail)
{
  local_alert="/var/log/snort/alert"
  if [[ -f "$local_alert" ]]; then
    echo "Snort最近告警(Top 20):"
    tail -20 "$local_alert" 2>/dev/null || true
  else
    echo "Snort alert log not found: $local_alert"
  fi
} | write_atomically "$LOG_DIR/dashboard_snort.txt"

# Syslog tail
{
  if [[ -f /var/log/syslog ]]; then
    echo "系统日志(/var/log/syslog)最近20行:"
    tail -20 /var/log/syslog 2>/dev/null || true
  else
    echo "syslog not found; try: journalctl -n 20"
    journalctl -n 20 2>/dev/null || true
  fi
} | write_atomically "$LOG_DIR/dashboard_syslog.txt"

# Meta
{
  echo "last_collect_epoch=$(date +%s)"
  echo "last_collect_time=$(date '+%Y-%m-%d %H:%M:%S')"
} | write_atomically "$LOG_DIR/dashboard_meta.txt"

