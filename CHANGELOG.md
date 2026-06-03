# Changelog

## 0.1.3 - 2026-06-03

- Analyze access logs modified within the last 7 days.
- Add endpoint statistics, PHP endpoint statistics, and PHP interactive endpoint summaries.
- Filter common attack/scanner paths from endpoint usage statistics.

## 0.1.2 - 2026-06-03

- Add an Executive Summary at the top of reports.
- Fix public-port detection to inspect the local listen address instead of peer address text.
- Reduce URL/callback noise by skipping common dependency directories.

## 0.1.1 - 2026-06-03

- Print absolute report paths after audit completion.
- Return report ownership to the sudo-invoking user when possible.
- Document how to fix root-owned reports created by older versions.
- Add visible audit progress output.

## 0.1.0 - 2026-06-03

- Initial open-source release.
- Added read-only Linux VM audit script.
- Added installer, uninstaller, reports, smoke test, docs, and GitHub release workflow.
