# VM Audit Report

- Generated: 2026-06-03 01:00:00 UTC
- Hostname: legacy-vm
- Tool Version: 0.1.0

## Security Notice

This report was produced by a read-only audit. The tool does not modify firewall rules, DNS, services, or application files.

## Potential Public Services

```text
tcp LISTEN 0 4096 0.0.0.0:80   0.0.0.0:* users:(("nginx",pid=881,fd=6))
tcp LISTEN 0 4096 0.0.0.0:8929 0.0.0.0:* users:(("gitlab",pid=1000,fd=7))
```

## Docker Containers

```text
NAMES      IMAGE                 PORTS                  STATUS
gitlab     gitlab/gitlab-ce      0.0.0.0:8929->80/tcp   Up 48 days
```

## URL and Callback Scan

```text
/var/www/app/config.php:$webhook = "https://discord.com/api/webhooks/***";
/var/www/app/.env:CALLBACK_URL=https://example.com/payment/callback
```

## Risk Scoring

- **HIGH**: Public listening service - tcp LISTEN 0 4096 0.0.0.0:8929 0.0.0.0:* users:(("gitlab",pid=1000,fd=7))
- **HIGH**: GitLab detected - Confirm repositories, runners, webhooks, backups, and external URL.
- **MEDIUM**: URL or callback references detected - Review integrations before shutdown.
- **LOW**: Local-only Redis - Redis is bound to 127.0.0.1 only.

## Migration Checklist

[ ] DNS transferred
[ ] SSL transferred
[ ] Access logs show no traffic
[ ] Docker backed up
[ ] Database backed up
[ ] Cron disabled
[ ] Callback confirmed
[ ] VM ready for shutdown
