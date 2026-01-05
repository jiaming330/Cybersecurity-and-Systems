# 模块说明

## 1. traffic_monitor（网络流量监控）

脚本：`scripts/traffic_monitor.sh`

- 通过 `/sys/class/net/<iface>/statistics/*` 读取接口累计字节/包数
- 结合 `netstat` 统计连接状态（ESTABLISHED / TIME_WAIT / SYN_RECV）
- 在 daemon 模式下按固定间隔写入日志：
  - `traffic_monitor.log`
  - `traffic_alerts.log`

> 说明：端口扫描 / DDoS 检测为**阈值启发式**，并非严格 IDS 规则。

### 使用方式

```bash
sudo /usr/local/bin/traffic_monitor.sh daemon
sudo /usr/local/bin/traffic_monitor.sh realtime
sudo /usr/local/bin/traffic_monitor.sh once
```

## 2. internal_monitor（内网/主机异常监控）

脚本：`scripts/internal_monitor.sh`

- ARP 欺骗（启发式）：同一 MAC 出现多个 IP
- 端口扫描：SYN_RECV 超阈值，并输出 Top 扫描源 IP
- ICMP flood：基于 `netstat -s` 的粗略统计
- 异常连接数：与过多不同 IP 建立连接
- 可疑端口：检测常见后门端口（4444/5555/6666/31337/12345）
- DNS 隧道：对 UDP/53 小采样捕获，若频率异常则告警（启发式）
- 内网主机发现：nmap ping 扫描

### 使用方式

```bash
sudo /usr/local/bin/internal_monitor.sh daemon
sudo /usr/local/bin/internal_monitor.sh realtime
sudo /usr/local/bin/internal_monitor.sh scan
sudo /usr/local/bin/internal_monitor.sh map
```

## 3. collector（面板快照采集）

脚本：`scripts/collect_dashboard_data.sh`

- 由 systemd timer 周期运行（默认 5 秒）
- 收集系统/网络/防火墙/Snort/系统日志快照
- 写入 `dashboard_*.txt`，供 PHP 面板只读读取

### 相关单元

- `systemd/security-monitor-collector.service`
- `systemd/security-monitor-collector.timer`

## 4. web dashboard（PHP 面板）

文件：`web/security_dashboard.php`

- 不执行系统命令，仅 `file_get_contents` 读取快照
- 前端每 5 秒刷新页面

## 5. Snort 自定义规则

文件：`snort/local.rules`

- 示例规则覆盖：SQL 注入 / XSS / 扫描 / DDoS / 数据泄露等
- 仅用于演示与课程设计，真实环境建议使用官方规则集并结合业务特征调优
