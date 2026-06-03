# Report Format

`vm-audit` writes a report directory with human-readable summaries and raw command output:

```text
vm-audit-report/
├── report.md
├── report.html
└── raw/
```

## report.md

The Markdown report is optimized for GitHub. It includes:

- System information
- Listening ports and potential public services
- Docker inventory
- PHP application and config inventory
- URL and callback references
- Apache and Nginx summaries
- SSL certificate summary
- Access log samples and top counters
- Cron and systemd inventory
- Firewall output
- Special service detection
- Risk scoring
- Migration checklist

## report.html

The HTML report is a single file with embedded CSS. It does not use CDN assets.

## raw/

The `raw/` directory stores command output and intermediate scan files. Use it when the Markdown summary needs verification.

## Risk Levels

- `LOW`: Local-only or informational findings.
- `MEDIUM`: Services, callbacks, certificates, logs, or scheduled work that need review.
- `HIGH`: Public listeners, database dependencies, GitLab, or scheduled jobs that may block shutdown.

Risk scoring is heuristic. Treat it as a triage aid, not as proof that a VM is safe to delete.
