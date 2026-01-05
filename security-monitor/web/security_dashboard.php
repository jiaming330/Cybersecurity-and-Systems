<?php
/**
 * Web安全监控面板（只读展示）
 *
 * 设计目标：
 * - 面板本身不执行任何系统命令（避免 shell_exec + sudo 风险）
 * - 通过 root 定时采集脚本将快照写入 /var/log/security_monitor/
 *
 * 依赖：
 * - scripts/collect_dashboard_data.sh + systemd timer
 */

declare(strict_types=1);

$LOG_DIR = '/var/log/security_monitor';

function safe_read(string $path, int $maxBytes = 200000): string {
    if (!is_file($path) || !is_readable($path)) {
        return "(无法读取: {$path})";
    }
    $content = file_get_contents($path, false, null, 0, $maxBytes);
    return $content === false ? "(读取失败: {$path})" : $content;
}

function last_updated(string $metaPath): string {
    if (!is_file($metaPath) || !is_readable($metaPath)) {
        return date('Y-m-d H:i:s');
    }
    $meta = file($metaPath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if ($meta === false) {
        return date('Y-m-d H:i:s');
    }
    foreach ($meta as $line) {
        if (str_starts_with($line, 'last_collect_time=')) {
            return substr($line, strlen('last_collect_time='));
        }
    }
    return date('Y-m-d H:i:s');
}

$systemTxt   = $LOG_DIR . '/dashboard_system.txt';
$networkTxt  = $LOG_DIR . '/dashboard_network.txt';
$firewallTxt = $LOG_DIR . '/dashboard_firewall.txt';
$snortTxt    = $LOG_DIR . '/dashboard_snort.txt';
$syslogTxt   = $LOG_DIR . '/dashboard_syslog.txt';
$metaTxt     = $LOG_DIR . '/dashboard_meta.txt';

$updatedAt = last_updated($metaTxt);
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Web安全监控面板</title>
    <script>
        // 前端每5秒刷新一次页面；后端快照由 root 侧定时采集。
        setTimeout(() => location.reload(), 5000);
    </script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: #fff;
            padding: 20px;
            min-height: 100vh;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        .header {
            text-align: center;
            padding: 30px 0;
            background: rgba(255,255,255,0.1);
            border-radius: 10px;
            margin-bottom: 30px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.3);
        }
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.5);
        }
        .header p { font-size: 1.1em; opacity: 0.9; }
        .dashboard-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .card {
            background: rgba(255,255,255,0.15);
            border-radius: 10px;
            padding: 20px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.3);
            backdrop-filter: blur(10px);
        }
        .card h3 {
            font-size: 1.3em;
            margin-bottom: 15px;
            padding-bottom: 10px;
            border-bottom: 2px solid rgba(255,255,255,0.3);
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .card pre {
            background: rgba(0,0,0,0.3);
            padding: 15px;
            border-radius: 5px;
            font-size: 0.9em;
            overflow-x: auto;
            max-height: 320px;
            overflow-y: auto;
            line-height: 1.6;
            white-space: pre-wrap;
            word-break: break-word;
        }
        .refresh-info {
            text-align: center;
            padding: 15px;
            background: rgba(255,255,255,0.1);
            border-radius: 10px;
            margin-top: 20px;
        }
        .refresh-info span { color: #4CAF50; font-weight: bold; }
        .hint {
            margin-top: 10px;
            font-size: 0.9em;
            opacity: 0.9;
        }
        @media (max-width: 768px) {
            .dashboard-grid { grid-template-columns: 1fr; }
            .header h1 { font-size: 1.8em; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔐 Web安全监控面板</h1>
            <p>基于Kali Linux的轻量级Web安全监控系统</p>
            <p class="hint">提示：如页面内容为空，请先确保 systemd 定时采集服务已启动（security-monitor-collector.timer）</p>
        </div>

        <div class="dashboard-grid">
            <div class="card">
                <h3>📊 系统状态</h3>
                <pre><?= htmlspecialchars(safe_read($systemTxt)) ?></pre>
            </div>

            <div class="card">
                <h3>🌐 网络连接</h3>
                <pre><?= htmlspecialchars(safe_read($networkTxt)) ?></pre>
            </div>

            <div class="card">
                <h3>🛡️ 防火墙状态</h3>
                <pre><?= htmlspecialchars(safe_read($firewallTxt)) ?></pre>
            </div>

            <div class="card">
                <h3>⚠️ Snort告警</h3>
                <pre><?= htmlspecialchars(safe_read($snortTxt)) ?></pre>
            </div>

            <div class="card">
                <h3>📈 流量监控日志（Tail）</h3>
                <pre><?= htmlspecialchars(safe_read($LOG_DIR . '/traffic_monitor.log')) ?></pre>
            </div>

            <div class="card">
                <h3>📝 系统日志（Tail）</h3>
                <pre><?= htmlspecialchars(safe_read($syslogTxt)) ?></pre>
            </div>
        </div>

        <div class="refresh-info">
            <p>页面每 <span>5</span> 秒自动刷新 | 最后采集更新时间: <span><?= htmlspecialchars($updatedAt) ?></span></p>
        </div>
    </div>
</body>
</html>
