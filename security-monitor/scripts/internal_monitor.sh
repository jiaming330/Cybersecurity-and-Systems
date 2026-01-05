#!/usr/bin/env bash
# ------------------------------------------------------------
# internal_monitor.sh
#
# Lightweight internal network / host anomaly monitor.
#
# Modes:
#   daemon   (default)  Periodic checks + logging (recommended for systemd)
#   realtime            Terminal dashboard (Ctrl+C to stop)
#   scan                Run checks once and exit
#   map                 Generate a basic host list to /tmp/network_map.txt
#   help                Show usage
#
# Logs (default):
#   /var/log/security_monitor/internal_monitor.log
#   /var/log/security_monitor/internal_alerts.log
# ------------------------------------------------------------

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
: "${INTERNAL_SCAN_THRESHOLD:=10}"
: "${INTERNAL_UNUSUAL_FOREIGN_IPS_THRESHOLD:=50}"
: "${INTERNAL_DAEMON_INTERVAL_SEC:=60}"

LOG_FILE="$LOG_DIR/internal_monitor.log"
ALERT_LOG="$LOG_DIR/internal_alerts.log"

mkdir -p "$LOG_DIR"

a_log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE" >/dev/null
}

a_alert() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🚨 $*" | tee -a "$ALERT_LOG" >/dev/null
  a_log "ALERT: $*"
}

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [mode]

Modes:
  daemon    Periodic checks + logging (default)
  realtime  Terminal dashboard
  scan      Run checks once
  map       Generate basic network map to /tmp/network_map.txt
  help      Show this message

Config (optional):
  /etc/security_monitor/security_monitor.conf

Logs:
  $LOG_FILE
  $ALERT_LOG
USAGE
}

detect_arp_spoofing() {
  local arp_output mac_count suspicious_mac
  arp_output=$(arp -n 2>/dev/null | grep -v "incomplete" || true)
  if [[ -z "$arp_output" ]]; then
    return 0
  fi
  mac_count=$(echo "$arp_output" | awk '{print $3}' | sort | uniq -c | sort -rn | head -1 | awk '{print $1+0}')

  # If any single MAC appears more than once, it may be normal (gateway etc).
  # We alert only when it maps to many IPs (heuristic).
  if (( mac_count >= 3 )); then
    suspicious_mac=$(echo "$arp_output" | awk '{print $3}' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
    a_alert "Possible ARP spoofing: MAC $suspicious_mac appears $mac_count times in ARP table"
    return 1
  fi
  return 0
}

detect_port_scan() {
  local syn_count
  syn_count=$(netstat -ant 2>/dev/null | awk '$6=="SYN_RECV"{c++} END{print c+0}')
  if (( syn_count > INTERNAL_SCAN_THRESHOLD )); then
    a_alert "Possible port scan: SYN_RECV=$syn_count (threshold=$INTERNAL_SCAN_THRESHOLD)"
    netstat -ant 2>/dev/null | awk '$6=="SYN_RECV"{print $5}' | cut -d':' -f1 | sort | uniq -c | sort -rn | head -5 | while read -r count ip; do
      a_alert "Top scanning IP: $ip ($count attempts)"
    done
    return 1
  fi
  return 0
}

detect_icmp_flood() {
  # netstat -s output differs across distros; best-effort
  local icmp_count
  icmp_count=$(netstat -s 2>/dev/null | awk '/ICMP messages received/{print $4; exit}')
  if [[ -n "${icmp_count:-}" ]] && [[ "$icmp_count" =~ ^[0-9]+$ ]] && (( icmp_count > 100 )); then
    a_alert "Possible ICMP flood: received=$icmp_count"
    return 1
  fi
  return 0
}

detect_unusual_connections() {
  local foreign_ips
  foreign_ips=$(netstat -ant 2>/dev/null | awk '$6=="ESTABLISHED"{print $5}' | cut -d':' -f1 | sort -u | wc -l | tr -d ' ')
  if (( foreign_ips > INTERNAL_UNUSUAL_FOREIGN_IPS_THRESHOLD )); then
    a_alert "Unusual number of remote peers: peers=$foreign_ips (threshold=$INTERNAL_UNUSUAL_FOREIGN_IPS_THRESHOLD)"
    return 1
  fi
  return 0
}

scan_internal_network() {
  local network_range
  network_range=$(ip route 2>/dev/null | awk '/^[0-9]/{if($1!="default"){print $1; exit}}')
  network_range=${network_range:-"192.168.1.0/24"}

  a_log "Scanning LAN: $network_range"
  local active_hosts
  active_hosts=$(nmap -sn "$network_range" 2>/dev/null | grep -c "Nmap scan report" || true)
  a_log "Active hosts: $active_hosts"
  echo "$active_hosts"
}

check_suspicious_ports() {
  local suspicious
  suspicious=$(netstat -tuln 2>/dev/null | grep -E ":(4444|5555|6666|31337|12345)" || true)
  if [[ -n "$suspicious" ]]; then
    local n
    n=$(echo "$suspicious" | wc -l | tr -d ' ')
    a_alert "Suspicious ports detected: count=$n"
    echo "$suspicious" | while read -r line; do
      a_alert "Suspicious port: $line"
    done
    return 1
  fi
  return 0
}

check_dns_tunneling() {
  # Heuristic only: count DNS packets in small capture
  local dns_queries
  dns_queries=$(tcpdump -i any -n -c 50 'udp port 53' 2>/dev/null | wc -l | tr -d ' ')
  if (( dns_queries > 30 )); then
    a_alert "Possible DNS tunneling: high DNS packet rate ($dns_queries/50 packets)"
    return 1
  fi
  return 0
}

generate_network_map() {
  local network_range
  network_range=$(ip route 2>/dev/null | awk '/^[0-9]/{if($1!="default"){print $1; exit}}')
  network_range=${network_range:-"192.168.1.0/24"}

  a_log "Generating network map for: $network_range"
  {
    echo "=== Network map ($network_range) ==="
    nmap -sn "$network_range" 2>/dev/null | grep "Nmap scan report" || true
  } > /tmp/network_map.txt
  a_log "Network map saved to /tmp/network_map.txt"
}

run_checks_once() {
  a_log "=== internal monitor checks start ==="
  detect_port_scan || true
  detect_arp_spoofing || true
  detect_icmp_flood || true
  detect_unusual_connections || true
  check_suspicious_ports || true
  check_dns_tunneling || true

  local active_hosts
  active_hosts=$(scan_internal_network)
  a_log "Checks done. active_hosts=$active_hosts"
}

realtime_loop() {
  a_log "=== internal monitor started (realtime) ==="
  while true; do
    if [[ -t 1 ]]; then
      clear || true
    fi
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          🔍 内网安全监控系统 - 实时监控                   ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "📅 时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    detect_port_scan || true
    detect_arp_spoofing || true
    detect_icmp_flood || true
    detect_unusual_connections || true
    check_suspicious_ports || true

    local established listening
    established=$(netstat -ant 2>/dev/null | awk '$6=="ESTABLISHED"{c++} END{print c+0}')
    listening=$(netstat -tuln 2>/dev/null | wc -l | tr -d ' ')

    echo "📊 简要统计: ESTABLISHED=$established  LISTEN=$listening"
    echo "📝 日志: $LOG_FILE"
    echo "🚨 告警: $ALERT_LOG"
    echo "按 Ctrl+C 停止"

    sleep 5
  done
}

daemon_loop() {
  a_log "=== internal monitor started (daemon) interval=${INTERNAL_DAEMON_INTERVAL_SEC}s ==="
  while true; do
    run_checks_once
    sleep "$INTERNAL_DAEMON_INTERVAL_SEC"
  done
}

cleanup() {
  a_log "=== internal monitor stopped ==="
}
trap cleanup INT TERM

MODE="${1:-daemon}"
case "$MODE" in
  daemon)   daemon_loop ;;
  realtime) realtime_loop ;;
  scan)     run_checks_once ;;
  map)      generate_network_map ;;
  help|-h|--help) usage ;;
  *)
    echo "Unknown mode: $MODE" >&2
    usage
    exit 1
    ;;
 esac
