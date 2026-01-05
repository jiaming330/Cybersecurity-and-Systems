# 部署指南

## 1. 环境要求

- 推荐：Kali Linux（Debian 系）
- Root 权限（安装、iptables、snort、tcpdump 等均需要）
- Apache + PHP（本项目使用 PHP 只读展示快照）

> 生产环境部署前请评估安全风险与性能影响，建议先在虚拟机/实验环境测试。

## 2. 一键安装

```bash
sudo ./scripts/install.sh
```

安装内容：
- 安装依赖包：Apache、PHP、Snort、Fail2ban、nmap、tcpdump...
- 部署面板：`/var/www/html/security_dashboard.php`
- 安装脚本：`/usr/local/bin/traffic_monitor.sh`、`/usr/local/bin/internal_monitor.sh`、`/usr/local/bin/collect_dashboard_data.sh`
- 安装配置：`/etc/security_monitor/security_monitor.conf`
- 安装并启动 systemd 单元：
  - `traffic-monitor`
  - `internal-monitor`
  - `security-monitor-collector.timer`

## 3. 访问面板

- `http://<你的IP>/security_dashboard.php`

> 若内容为空，请检查 `security-monitor-collector.timer` 是否运行。

## 4. （可选）配置防火墙

⚠️ **高风险**：会重置 iptables 并默认 DROP。

```bash
sudo ./scripts/install.sh --with-firewall
```

建议：
- 远程部署前先把 SSH 端口改成实际端口
- 添加管理 IP 白名单
- 结合业务端口与反向代理/负载均衡拓扑调整

## 5. 日志位置

默认统一写入：`/var/log/security_monitor/`

- `traffic_monitor.log` / `traffic_alerts.log`
- `internal_monitor.log` / `internal_alerts.log`
- `dashboard_*.txt`（collector 快照）

