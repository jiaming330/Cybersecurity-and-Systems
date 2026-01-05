# 常见问题排查

## 1) 面板访问正常但内容为空/提示无法读取

- 检查采集 timer：

```bash
systemctl status security-monitor-collector.timer
systemctl status security-monitor-collector.service
```

- 手动执行采集脚本：

```bash
sudo /usr/local/bin/collect_dashboard_data.sh
ls -l /var/log/security_monitor/dashboard_*.txt
```

- 检查权限：面板进程需要读取 `/var/log/security_monitor/` 下的快照文件（默认 0644）。

## 2) traffic-monitor / internal-monitor 启动失败

- 查看详细日志：

```bash
journalctl -u traffic-monitor -n 50 --no-pager
journalctl -u internal-monitor -n 50 --no-pager
```

- 确认依赖工具已安装：`netstat`（net-tools）、`tcpdump`、`nmap` 等。

## 3) 运行 `--with-firewall` 后 SSH 断开

这是预期风险：iptables 被重置并默认 DROP。

建议：
- 在本地/虚拟机测试规则
- 在应用规则前先把 **实际 SSH 端口** 写入规则
- 增加管理网段白名单，如：
  - `iptables -A INPUT -s <你的管理IP>/32 -p tcp --dport <ssh_port> -j ACCEPT`

## 4) Snort 没有告警

- 检查 Snort 服务：

```bash
systemctl status snort
```

- 检查告警日志路径是否存在：`/var/log/snort/alert`
- 确认 Snort 已加载 `local.rules`（不同发行版 Snort 配置文件路径可能不同，需要手动确认）。
