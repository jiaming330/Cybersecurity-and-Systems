#!/usr/bin/env bash
# ------------------------------------------------------------
# install.sh
#
# One-click installer for the "Lightweight Web Security Monitor".
#
# What this installer does:
# - Installs required packages (Apache, PHP, Snort, Fail2ban, tools)
# - Deploys the web dashboard to Apache web root
# - Installs monitoring scripts into /usr/local/bin
# - Copies config to /etc/security_monitor
# - Installs systemd unit files and starts services
#
# Safety notes:
# - Firewall configuration is DISABLED by default (must opt-in with --with-firewall)
# - Recommended to run in a VM / lab environment first
# ------------------------------------------------------------

set -euo pipefail

PROJECT_NAME="基于Kali的轻量级Web安全监控系统"
PROJECT_VERSION="1.0"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

WITH_FIREWALL=0
YES=0
SKIP_APT_UPDATE=0
WEB_ROOT="/var/www/html"

usage() {
  cat <<USAGE
Usage: sudo $0 [options]

Options:
  --with-firewall        Apply iptables rules (DANGEROUS on remote servers)
  --yes                  Non-interactive: assume yes for prompts
  --skip-apt-update       Skip apt update
  --web-root <dir>        Apache web root (default: /var/www/html)
  -h, --help             Show this help

Examples:
  sudo $0
  sudo $0 --with-firewall
  sudo $0 --web-root /var/www/html
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-firewall) WITH_FIREWALL=1; shift ;;
    --yes) YES=1; shift ;;
    --skip-apt-update) SKIP_APT_UPDATE=1; shift ;;
    --web-root) WEB_ROOT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "错误: 请使用root权限运行此脚本" >&2
    echo "使用方法: sudo $0" >&2
    exit 1
  fi
}

LOG_DIR="/var/log/security_monitor"
INSTALL_LOG="$LOG_DIR/install.log"

log() {
  mkdir -p "$LOG_DIR"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$INSTALL_LOG"
}

confirm() {
  local prompt="$1"
  if (( YES == 1 )); then
    return 0
  fi
  read -r -p "$prompt [y/N]: " ans
  [[ "${ans}" == "y" || "${ans}" == "Y" ]]
}

check_kali() {
  if [[ ! -f /etc/kali-release ]]; then
    log "警告: 未检测到 /etc/kali-release，可能不是Kali Linux。"
    if ! confirm "继续安装?"; then
      exit 1
    fi
  fi
}

apt_update() {
  if (( SKIP_APT_UPDATE == 1 )); then
    log "跳过 apt update"
    return 0
  fi
  log "正在更新 apt 索引..."
  apt update
}

install_deps() {
  log "正在安装依赖包..."
  apt install -y \
    apache2 php php-cli \
    snort iptables-persistent fail2ban \
    nmap tcpdump net-tools curl wget git vim bc
}

deploy_dashboard() {
  log "部署 Web 监控面板..."
  mkdir -p "$WEB_ROOT"
  cp "$ROOT_DIR/web/security_dashboard.php" "$WEB_ROOT/security_dashboard.php"
  chmod 0644 "$WEB_ROOT/security_dashboard.php"
  log "Dashboard -> $WEB_ROOT/security_dashboard.php"

  systemctl enable apache2
  systemctl restart apache2
}

install_scripts_and_config() {
  log "安装脚本与配置..."

  install -m 0755 "$ROOT_DIR/scripts/traffic_monitor.sh" /usr/local/bin/traffic_monitor.sh
  install -m 0755 "$ROOT_DIR/scripts/internal_monitor.sh" /usr/local/bin/internal_monitor.sh
  install -m 0755 "$ROOT_DIR/scripts/collect_dashboard_data.sh" /usr/local/bin/collect_dashboard_data.sh

  mkdir -p /etc/security_monitor
  install -m 0644 "$ROOT_DIR/config/security_monitor.conf" /etc/security_monitor/security_monitor.conf

  mkdir -p "$LOG_DIR"
  touch "$LOG_DIR/traffic_monitor.log" "$LOG_DIR/traffic_alerts.log" \
        "$LOG_DIR/internal_monitor.log" "$LOG_DIR/internal_alerts.log"
  chmod 0644 "$LOG_DIR"/*.log || true
}

configure_snort() {
  log "配置 Snort..."
  if [[ -f "$ROOT_DIR/snort/local.rules" ]]; then
    mkdir -p /etc/snort/rules
    install -m 0644 "$ROOT_DIR/snort/local.rules" /etc/snort/rules/local.rules
    log "Snort rules -> /etc/snort/rules/local.rules"
  fi

  # Best-effort: start service if exists
  systemctl enable snort 2>/dev/null || true
  systemctl restart snort 2>/dev/null || log "提示: Snort 服务启动失败（不同系统的 service 名称可能不同）"
}

configure_fail2ban() {
  log "配置 Fail2ban..."
  cat > /etc/fail2ban/jail.local <<'JAIL'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[apache-auth]
enabled = true
port = http,https
logpath = /var/log/apache2/error.log
maxretry = 3
bantime = 3600
JAIL

  systemctl enable fail2ban 2>/dev/null || true
  systemctl restart fail2ban 2>/dev/null || log "提示: Fail2ban 服务启动失败"
}

install_systemd_units() {
  log "安装 systemd 单元文件..."
  install -m 0644 "$ROOT_DIR/systemd/traffic-monitor.service" /etc/systemd/system/traffic-monitor.service
  install -m 0644 "$ROOT_DIR/systemd/internal-monitor.service" /etc/systemd/system/internal-monitor.service
  install -m 0644 "$ROOT_DIR/systemd/security-monitor-collector.service" /etc/systemd/system/security-monitor-collector.service
  install -m 0644 "$ROOT_DIR/systemd/security-monitor-collector.timer" /etc/systemd/system/security-monitor-collector.timer

  systemctl daemon-reload

  systemctl enable traffic-monitor internal-monitor security-monitor-collector.timer
  systemctl restart traffic-monitor internal-monitor
  systemctl start security-monitor-collector.timer
}

apply_firewall_rules() {
  log "准备配置防火墙 (iptables)..."
  cat <<WARN
⚠️  高风险操作：iptables 将被重置并设置默认 DROP。
    如果你在远程服务器上操作，可能会把自己锁在外面。
    建议：先在虚拟机/本地环境测试；或根据实际 SSH 端口/IP 白名单调整脚本。
WARN

  if ! confirm "确认继续应用防火墙规则?"; then
    log "已跳过防火墙配置"
    return 0
  fi

  # Reset rules
  iptables -F
  iptables -X
  iptables -Z

  # Basic allow
  iptables -A INPUT -i lo -j ACCEPT
  iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # Allow SSH/HTTP/HTTPS
  iptables -A INPUT -p tcp --dport 22 -j ACCEPT
  iptables -A INPUT -p tcp --dport 80 -j ACCEPT
  iptables -A INPUT -p tcp --dport 443 -j ACCEPT

  # Allow ping (optional)
  iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

  # Default deny
  iptables -P INPUT DROP

  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
  else
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
  fi

  log "防火墙规则已应用"
}

create_uninstall() {
  log "创建卸载脚本..."
  cat > /usr/local/bin/security_monitor_uninstall.sh <<'EOF_UN'
#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="/var/log/security_monitor"

echo "Stopping services..."
systemctl stop traffic-monitor internal-monitor security-monitor-collector.timer 2>/dev/null || true
systemctl disable traffic-monitor internal-monitor security-monitor-collector.timer 2>/dev/null || true

rm -f /etc/systemd/system/traffic-monitor.service
rm -f /etc/systemd/system/internal-monitor.service
rm -f /etc/systemd/system/security-monitor-collector.service
rm -f /etc/systemd/system/security-monitor-collector.timer
systemctl daemon-reload

rm -f /usr/local/bin/traffic_monitor.sh
rm -f /usr/local/bin/internal_monitor.sh
rm -f /usr/local/bin/collect_dashboard_data.sh
rm -rf /etc/security_monitor

rm -f /var/www/html/security_dashboard.php

echo "(Optional) logs kept at: $LOG_DIR"
echo "Uninstall complete."
EOF_UN
  chmod +x /usr/local/bin/security_monitor_uninstall.sh
}

show_info() {
  local ip
  ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  echo ""
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║                    安装完成！                              ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""
  echo "📊 Web监控面板: http://${ip:-127.0.0.1}/security_dashboard.php"
  echo "📝 安装日志: $INSTALL_LOG"
  echo ""
  echo "systemd 服务:"
  echo "  traffic-monitor               (网络流量监控)"
  echo "  internal-monitor              (内网/主机异常监控)"
  echo "  security-monitor-collector.timer (面板快照采集)"
  echo ""
  echo "常用命令:"
  echo "  systemctl status traffic-monitor"
  echo "  systemctl status internal-monitor"
  echo "  systemctl status security-monitor-collector.timer"
  echo ""
  echo "卸载: /usr/local/bin/security_monitor_uninstall.sh"
}

main() {
  require_root
  check_kali

  log "开始安装: $PROJECT_NAME v$PROJECT_VERSION"

  apt_update
  install_deps

  deploy_dashboard
  install_scripts_and_config
  install_systemd_units

  configure_snort
  configure_fail2ban

  if (( WITH_FIREWALL == 1 )); then
    apply_firewall_rules
  else
    log "默认跳过防火墙配置（如需启用，请使用 --with-firewall）"
  fi

  create_uninstall

  log "安装完成"
  show_info
}

trap 'echo "安装过程中断"; exit 1' INT TERM
main
