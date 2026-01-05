#!/usr/bin/env bash
# ------------------------------------------------------------
# traffic_monitor.sh
#
# Lightweight network traffic + connection monitor.
#
# Modes:
#   daemon   (default)  Periodically sample interface counters and connection stats,
#                       write results to log files (recommended for systemd).
#   realtime            Render a simple terminal dashboard (Ctrl+C to stop).
#   once                Collect one sample and exit.
#   help                Show usage.
#
# Config:
#   Reads /etc/security_monitor/security_monitor.conf if present,
#   otherwise uses the repo config at ../config/security_monitor.conf.
# ------------------------------------------------------------

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load config (best-effort)
load_config() {
  local candidates=(
    "/etc/security_monitor/security_monitor.conf"
    "$SCRIPT_DIR/../config/security_monitor.conf"
  )
  for f in "${candidates[@]}"; do
    if [[ -f "$f" ]]; then
      # shellcheck disable=SC1090
      source "$f"
      return 0
    fi
  done
  return 0
}

load_config

: "${LOG_DIR:=/var/log/security_monitor}"
: "${TRAFFIC_INTERFACE:=}"
: "${TRAFFIC_INTERVAL_SEC:=2}"
: "${PORT_SCAN_SYN_THRESHOLD:=20}"
: "${DDOS_ESTABLISHED_THRESHOLD:=500}"

LOG_FILE="$LOG_DIR/traffic_monitor.log"
ALERT_LOG="$LOG_DIR/traffic_alerts.log"

mkdir -p "$LOG_DIR"

log_line() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE" >/dev/null
}

alert_line() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🚨 $*" | tee -a "$ALERT_LOG" >/dev/null
  log_line "ALERT: $*"
}

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [mode]

Modes:
  daemon    Periodic logging (default)
  realtime  Terminal dashboard
  once      Collect one sample and exit
  help      Show this message

Config (optional):
  /etc/security_monitor/security_monitor.conf

Logs:
  $LOG_FILE
  $ALERT_LOG
USAGE
}

detect_iface() {
  if [[ -n "${TRAFFIC_INTERFACE}" ]]; then
    echo "$TRAFFIC_INTERFACE"
    return 0
  fi
  local iface
  iface=$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')
  echo "${iface:-eth0}"
}

read_iface_stats() {
  local iface="$1"
  local rx tx rxp txp
  rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
  tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)
  rxp=$(cat "/sys/class/net/$iface/statistics/rx_packets" 2>/dev/null || echo 0)
  txp=$(cat "/sys/class/net/$iface/statistics/tx_packets" 2>/dev/null || echo 0)
  echo "$rx,$tx,$rxp,$txp"
}

calc_kbps() {
  local old="$1" new="$2" interval="$3"
  local old_rx new_rx old_tx new_tx
  old_rx=$(cut -d',' -f1 <<<"$old")
  new_rx=$(cut -d',' -f1 <<<"$new")
  old_tx=$(cut -d',' -f2 <<<"$old")
  new_tx=$(cut -d',' -f2 <<<"$new")

  # Prevent negative values if counters reset
  local rx_diff=$(( new_rx > old_rx ? new_rx - old_rx : 0 ))
  local tx_diff=$(( new_tx > old_tx ? new_tx - old_tx : 0 ))

  local rx_kbps=$(( rx_diff * 8 / interval / 1024 ))
  local tx_kbps=$(( tx_diff * 8 / interval / 1024 ))
  echo "$rx_kbps,$tx_kbps"
}

conn_counts() {
  local established time_wait syn_recv
  established=$(netstat -ant 2>/dev/null | awk '$6=="ESTABLISHED"{c++} END{print c+0}')
  time_wait=$(netstat -ant 2>/dev/null | awk '$6=="TIME_WAIT"{c++} END{print c+0}')
  syn_recv=$(netstat -ant 2>/dev/null | awk '$6=="SYN_RECV"{c++} END{print c+0}')
  echo "$established,$time_wait,$syn_recv"
}

top_remote_ips() {
  netstat -ant 2>/dev/null | awk '{print $5}' | cut -d':' -f1 | \
    grep -E '^[0-9]' | sort | uniq -c | sort -rn | head -5
}

active_ports() {
  netstat -tuln 2>/dev/null | awk '{print $4}' | awk -F':' '{print $NF}' | \
    grep -E '^[0-9]+$' | sort | uniq -c | sort -rn | head -5
}

check_thresholds() {
  local established="$1" syn_recv="$2"
  if (( syn_recv > PORT_SCAN_SYN_THRESHOLD )); then
    alert_line "Possible port scan: SYN_RECV=$syn_recv (threshold=$PORT_SCAN_SYN_THRESHOLD)"
  fi
  if (( established > DDOS_ESTABLISHED_THRESHOLD )); then
    alert_line "Possible DDoS: ESTABLISHED=$established (threshold=$DDOS_ESTABLISHED_THRESHOLD)"
  fi
}

collect_once() {
  local iface="$1"
  local old_stats="$2"

  sleep "$TRAFFIC_INTERVAL_SEC"

  local new_stats bandwidth rx_kbps tx_kbps cc established time_wait syn_recv
  new_stats=$(read_iface_stats "$iface")
  bandwidth=$(calc_kbps "$old_stats" "$new_stats" "$TRAFFIC_INTERVAL_SEC")
  rx_kbps=$(cut -d',' -f1 <<<"$bandwidth")
  tx_kbps=$(cut -d',' -f2 <<<"$bandwidth")

  cc=$(conn_counts)
  established=$(cut -d',' -f1 <<<"$cc")
  time_wait=$(cut -d',' -f2 <<<"$cc")
  syn_recv=$(cut -d',' -f3 <<<"$cc")

  log_line "iface=$iface rx_kbps=$rx_kbps tx_kbps=$tx_kbps established=$established time_wait=$time_wait syn_recv=$syn_recv"

  check_thresholds "$established" "$syn_recv"

  echo "$new_stats"
}

daemon_loop() {
  local iface
  iface=$(detect_iface)
  log_line "=== traffic monitor started (daemon) iface=$iface interval=${TRAFFIC_INTERVAL_SEC}s ==="

  local old_stats
  old_stats=$(read_iface_stats "$iface")

  while true; do
    old_stats=$(collect_once "$iface" "$old_stats")
  done
}

realtime_loop() {
  local iface
  iface=$(detect_iface)
  log_line "=== traffic monitor started (realtime) iface=$iface interval=${TRAFFIC_INTERVAL_SEC}s ==="

  local old_stats
  old_stats=$(read_iface_stats "$iface")

  while true; do
    if [[ -t 1 ]]; then
      clear || true
    fi

    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          🌐 网络流量监控系统 - 实时监控                   ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "📅 时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "🔌 接口: $iface"
    echo ""

    local new_stats bandwidth rx_kbps tx_kbps cc established time_wait syn_recv
    new_stats=$(read_iface_stats "$iface")
    bandwidth=$(calc_kbps "$old_stats" "$new_stats" "$TRAFFIC_INTERVAL_SEC")
    rx_kbps=$(cut -d',' -f1 <<<"$bandwidth")
    tx_kbps=$(cut -d',' -f2 <<<"$bandwidth")

    cc=$(conn_counts)
    established=$(cut -d',' -f1 <<<"$cc")
    time_wait=$(cut -d',' -f2 <<<"$cc")
    syn_recv=$(cut -d',' -f3 <<<"$cc")

    echo "📊 流量统计:"
    echo "   ↓ 接收速率: ${rx_kbps} Kbps"
    echo "   ↑ 发送速率: ${tx_kbps} Kbps"
    echo ""

    echo "🔗 连接状态:"
    echo "   ✓ 已建立: ${established}"
    echo "   ⏳ TIME_WAIT: ${time_wait}"
    echo "   ⚡ SYN_RECV: ${syn_recv}"
    echo ""

    echo "📈 Top连接IP:"
    top_remote_ips | while read -r count ip; do
      printf "   %-15s : %s 连接\n" "$ip" "$count"
    done
    echo ""

    echo "🎯 活跃端口:"
    active_ports | while read -r count port; do
      printf "   %-8s : %s 连接\n" "$port" "$count"
    done
    echo ""

    echo "📝 日志: $LOG_FILE"
    echo "按 Ctrl+C 停止"

    log_line "iface=$iface rx_kbps=$rx_kbps tx_kbps=$tx_kbps established=$established time_wait=$time_wait syn_recv=$syn_recv"
    check_thresholds "$established" "$syn_recv"

    old_stats="$new_stats"
    sleep "$TRAFFIC_INTERVAL_SEC"
  done
}

cleanup() {
  log_line "=== traffic monitor stopped ==="
}
trap cleanup INT TERM

MODE="${1:-daemon}"
case "$MODE" in
  daemon)   daemon_loop ;;
  realtime) realtime_loop ;;
  once)
    iface=$(detect_iface)
    old_stats=$(read_iface_stats "$iface")
    collect_once "$iface" "$old_stats" >/dev/null
    ;;
  help|-h|--help) usage ;;
  *)
    echo "Unknown mode: $MODE" >&2
    usage
    exit 1
    ;;
esac
