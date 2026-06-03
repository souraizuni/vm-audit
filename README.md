# vm-audit

`vm-audit` is a read-only Bash audit tool for old Linux VMs, VPS instances, and cloud hosts. It inventories likely public services and generates a readable report to help decide whether a machine can be safely decommissioned.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/souraizuni/vm-audit/main/install.sh | sudo bash
sudo vm-audit
```

During the audit, progress is printed to the terminal:

```text
vm-audit 0.1.2 starting read-only audit.
Report directory: /home/admin/vm-audit-report
[1/14] Collecting system information...
[1/14] Collecting system information complete.
[2/14] Scanning listening ports...
```

The report is written to:

```text
vm-audit-report/
├── report.md
├── report.html
└── raw/
```

The top of `report.md` and `report.html` contains an Executive Summary with:

- shutdown verdict
- key counts
- public entry points
- shutdown blockers
- suggested next actions

Detailed command output remains below the summary for verification.

By default, `vm-audit-report` is created in the directory where you run `sudo vm-audit`. The final lines print the exact absolute paths:

```text
Report written to /home/admin/vm-audit-report/report.md
HTML report written to /home/admin/vm-audit-report/report.html
Raw files written to /home/admin/vm-audit-report/raw
```

To choose a fixed location:

```bash
sudo vm-audit --output /tmp/vm-audit-report
```

If an older version created a root-owned report that your normal user cannot read, fix the existing report with:

```bash
sudo chown -R "$USER:$USER" ~/vm-audit-report
chmod -R u+rwX,go-rwx ~/vm-audit-report
```

Then update `vm-audit`:

```bash
curl -fsSL https://raw.githubusercontent.com/souraizuni/vm-audit/main/install.sh | sudo bash
vm-audit --version
```

## Supported Systems

- Ubuntu 18.04+
- Ubuntu 20.04+
- Debian 11+
- Debian 12+
- Rocky Linux
- AlmaLinux

## Features

- Executive Summary for shutdown decisions
- System inventory: hostname, kernel, OS release, IP addresses, routes
- Listening port scan using `ss -tulpn` or `netstat -tulpn`
- Public bind detection from the local listening address for `0.0.0.0`, `[::]`, `:::`, and `*`
- Docker inventory: containers, networks, volumes, compose files
- PHP website inventory under `/var/www`, `/srv`, and `/home`
- PHP config scan for MySQL, MariaDB, PostgreSQL, Redis, and MongoDB
- URL, webhook, and callback scan with basic secret masking and vendor-directory noise filtering
- Apache virtual host inventory
- Nginx config summary for `server_name`, `listen`, `root`, `proxy_pass`, and `fastcgi_pass`
- Certbot certificate summary
- Recent Nginx/Apache access log samples with top IP and URL summaries
- Cron inventory with `php`, `curl`, and `wget` highlighting
- Systemd running and enabled service inventory
- Firewall readout for UFW, iptables, and nftables
- GitLab, Minecraft, Grafana, Prometheus, and Loki detection
- Markdown and standalone HTML reports
- Automatic Low/Medium/High risk notes and migration checklist

## Sample Report

See [docs/examples/sample-report.md](docs/examples/sample-report.md).

Example risk entries:

```text
HIGH: Public listening service - tcp LISTEN 0 4096 0.0.0.0:8929 0.0.0.0:* users:(("gitlab",pid=1000,fd=7))
LOW: Local-only service - Redis bound to 127.0.0.1
```

## Security Notice

This tool is read-only. It does not modify:

- Firewall
- DNS
- Services
- Files

It only runs inventory commands and writes the generated report directory. Some checks need root privileges to see process names, service details, firewall rules, and protected logs.

## Usage

```bash
sudo vm-audit
sudo vm-audit --output /tmp/my-vm-audit-report
vm-audit --version
vm-audit uninstall
```

## Uninstall

```bash
sudo vm-audit uninstall
```

or:

```bash
sudo ./uninstall.sh
```

## Development

Run the smoke test:

```bash
bash tests/smoke-test.sh
```

The project intentionally avoids Python, Node.js, and Go runtime dependencies.
