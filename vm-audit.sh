#!/usr/bin/env bash
set -u

VERSION="0.1.0"
REPORT_DIR="${VM_AUDIT_REPORT_DIR:-vm-audit-report}"
RAW_DIR="$REPORT_DIR/raw"
MD="$REPORT_DIR/report.md"
HTML="$REPORT_DIR/report.html"
RISK_ITEMS="$RAW_DIR/risks.tsv"

umask 077

usage() {
  cat <<'EOF'
vm-audit - read-only Linux VM service audit

Usage:
  sudo vm-audit
  vm-audit --output /path/to/report-dir
  vm-audit uninstall
  vm-audit --version
EOF
}

say() {
  printf '%s\n' "$*"
}

progress() {
  printf '%s\n' "$*" >&2
}

run_step() {
  step_no="$1"
  step_total="$2"
  step_label="$3"
  shift 3
  progress "[$step_no/$step_total] $step_label..."
  "$@"
  progress "[$step_no/$step_total] $step_label complete."
}

have() {
  command -v "$1" >/dev/null 2>&1
}

run_raw() {
  name="$1"
  shift
  out="$RAW_DIR/$name.txt"
  {
    printf '$'
    for arg in "$@"; do printf ' %s' "$arg"; done
    printf '\n\n'
    "$@" 2>&1
  } >"$out"
}

append_section() {
  title="$1"
  file="$2"
  {
    printf '\n## %s\n\n' "$title"
    if [ -s "$file" ]; then
      printf '```text\n'
      sed 's/[[:cntrl:]]//g' "$file" | head -n 500
      printf '```\n'
    else
      printf '_No data found._\n'
    fi
  } >>"$MD"
}

write_raw_text() {
  file="$1"
  shift
  printf '%s\n' "$*" >"$RAW_DIR/$file.txt"
}

add_risk() {
  level="$1"
  title="$2"
  detail="$3"
  printf '%s\t%s\t%s\n' "$level" "$title" "$detail" >>"$RISK_ITEMS"
}

mask_sensitive() {
  sed -E \
    -e 's#(https?://discord(app)?\.com/api/webhooks/)[^[:space:]")'\''<>]+#\1***#Ig' \
    -e 's#(token=)[^&[:space:]")'\''<>]+#\1***#Ig' \
    -e 's#(api[_-]?key=)[^&[:space:]")'\''<>]+#\1***#Ig' \
    -e 's#(password=)[^&[:space:]")'\''<>]+#\1***#Ig' \
    -e 's#(passwd=)[^&[:space:]")'\''<>]+#\1***#Ig' \
    -e 's#(secret=)[^&[:space:]")'\''<>]+#\1***#Ig'
}

safe_find_roots() {
  for p in /var/www /srv /home; do
    [ -d "$p" ] && printf '%s\n' "$p"
  done
}

init_report() {
  case "$REPORT_DIR" in
    ""|"/"|".")
      say "Refusing unsafe report directory: $REPORT_DIR"
      exit 2
      ;;
  esac
  rm -rf "$REPORT_DIR"
  mkdir -p "$RAW_DIR"
  : >"$RISK_ITEMS"
  cat >"$MD" <<EOF
# VM Audit Report

- Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
- Hostname: $(hostname 2>/dev/null || printf unknown)
- Tool Version: $VERSION

## Security Notice

This report was produced by a read-only audit. The tool does not modify firewall rules, DNS, services, or application files.
EOF
}

audit_system() {
  run_raw hostname hostname
  run_raw uname uname -a
  if [ -r /etc/os-release ]; then cp /etc/os-release "$RAW_DIR/os-release.txt"; else write_raw_text os-release "not readable"; fi
  if have ip; then
    run_raw ip-addr ip addr
    run_raw ip-route ip route
  else
    write_raw_text ip-addr "ip command not found"
    write_raw_text ip-route "ip command not found"
  fi
  {
    cat "$RAW_DIR/hostname.txt" 2>/dev/null
    cat "$RAW_DIR/uname.txt" 2>/dev/null
    cat "$RAW_DIR/os-release.txt" 2>/dev/null
    cat "$RAW_DIR/ip-addr.txt" 2>/dev/null
    cat "$RAW_DIR/ip-route.txt" 2>/dev/null
  } >"$RAW_DIR/system-summary.txt"
  append_section "System Information" "$RAW_DIR/system-summary.txt"
}

audit_ports() {
  out="$RAW_DIR/ports.txt"
  if have ss; then
    run_raw ports ss -tulpn
  elif have netstat; then
    run_raw ports netstat -tulpn
  else
    write_raw_text ports "ss and netstat not found"
  fi
  grep -E '(^|[[:space:]])(0\.0\.0\.0|\[::\]|:::)' "$out" >"$RAW_DIR/public-ports.txt" 2>/dev/null || true
  grep -Ei '(127\.0\.0\.1|\[::1\]).*redis|redis.*(127\.0\.0\.1|\[::1\])' "$out" >"$RAW_DIR/local-redis.txt" 2>/dev/null || true
  while IFS= read -r line; do
    [ -n "$line" ] && add_risk "HIGH" "Public listening service" "$line"
  done <"$RAW_DIR/public-ports.txt"
  if [ -s "$RAW_DIR/local-redis.txt" ]; then
    add_risk "LOW" "Local-only Redis" "Redis appears bound to localhost only."
  fi
  append_section "Listening Ports" "$out"
  append_section "Potential Public Services" "$RAW_DIR/public-ports.txt"
}

audit_docker() {
  if have docker; then
    run_raw docker-ps docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}'
    run_raw docker-network docker network ls
    run_raw docker-volume docker volume ls
  else
    write_raw_text docker-ps "docker command not found"
    write_raw_text docker-network "docker command not found"
    write_raw_text docker-volume "docker command not found"
  fi
  find / -xdev \( -name docker-compose.yml -o -name compose.yml -o -name compose.yaml \) -print 2>/dev/null >"$RAW_DIR/docker-compose-files.txt" || true
  grep -Ei 'gitlab' "$RAW_DIR/docker-ps.txt" >/dev/null 2>&1 && add_risk "HIGH" "Docker GitLab detected" "Review external URL, exposed ports, repositories, and backups before shutdown."
  grep -Ei 'minecraft|itzg/minecraft' "$RAW_DIR/docker-ps.txt" >/dev/null 2>&1 && add_risk "MEDIUM" "Docker Minecraft detected" "Review player activity, world backups, and exposed ports."
  grep -Ei 'grafana|prometheus|loki' "$RAW_DIR/docker-ps.txt" >/dev/null 2>&1 && add_risk "MEDIUM" "Monitoring stack detected" "Grafana/Prometheus/Loki may still receive metrics or alerts."
  append_section "Docker Containers" "$RAW_DIR/docker-ps.txt"
  append_section "Docker Networks" "$RAW_DIR/docker-network.txt"
  append_section "Docker Volumes" "$RAW_DIR/docker-volume.txt"
  append_section "Compose Files" "$RAW_DIR/docker-compose-files.txt"
}

audit_php_sites() {
  roots="$(safe_find_roots)"
  out="$RAW_DIR/php-sites.txt"
  : >"$out"
  count_files=0
  count_dirs=0
  if [ -n "$roots" ]; then
    find $roots \( -name '*.php' -o -name index.php \) -type f -print 2>/dev/null >"$RAW_DIR/php-files.txt" || true
    count_files="$(wc -l <"$RAW_DIR/php-files.txt" | awk '{print $1}')"
    awk -F/ 'NF>3 {print "/"$2"/"$3"/"$4}' "$RAW_DIR/php-files.txt" | sort -u >"$RAW_DIR/php-site-roots.txt"
    count_dirs="$(wc -l <"$RAW_DIR/php-site-roots.txt" | awk '{print $1}')"
  else
    : >"$RAW_DIR/php-files.txt"
    : >"$RAW_DIR/php-site-roots.txt"
  fi
  {
    printf 'Website-like directories: %s\n' "$count_dirs"
    printf 'PHP files: %s\n\n' "$count_files"
    cat "$RAW_DIR/php-site-roots.txt"
  } >"$out"
  [ "$count_files" -gt 0 ] 2>/dev/null && add_risk "MEDIUM" "PHP application files detected" "$count_files PHP files under /var/www, /srv, or /home."
  append_section "PHP Website Inventory" "$out"
}

audit_php_config() {
  roots="$(safe_find_roots)"
  : >"$RAW_DIR/php-config-files.txt"
  : >"$RAW_DIR/php-dependencies.txt"
  if [ -n "$roots" ]; then
    find $roots \( -name '.env' -o -name config.php -o -name database.php \) -type f -print 2>/dev/null >"$RAW_DIR/php-config-files.txt" || true
    while IFS= read -r f; do
      [ -r "$f" ] || continue
      grep -EHi 'mysql|mariadb|pgsql|postgres|redis|mongodb|mongo' "$f" 2>/dev/null | mask_sensitive
    done <"$RAW_DIR/php-config-files.txt" >"$RAW_DIR/php-dependencies.txt"
  fi
  grep -Eiq 'mysql|mariadb|pgsql|postgres|mongodb|mongo' "$RAW_DIR/php-dependencies.txt" && add_risk "HIGH" "Database dependency detected" "Application config references database services."
  grep -Eiq 'redis' "$RAW_DIR/php-dependencies.txt" && add_risk "MEDIUM" "Redis dependency detected" "Application config references Redis."
  append_section "PHP Config Files" "$RAW_DIR/php-config-files.txt"
  append_section "PHP Service Dependencies" "$RAW_DIR/php-dependencies.txt"
}

audit_callbacks() {
  roots="$(safe_find_roots)"
  : >"$RAW_DIR/urls-callbacks.txt"
  if [ -n "$roots" ]; then
    find $roots -type f \( -name '*.php' -o -name '*.js' -o -name '*.json' -o -name '*.env' -o -name '*.yml' -o -name '*.yaml' -o -name '*.conf' -o -name '*.ini' \) -size -2M -print 2>/dev/null |
      while IFS= read -r f; do
        grep -EHi 'https?://|webhook|callback|discord|telegram|slack|line' "$f" 2>/dev/null | mask_sensitive
      done >"$RAW_DIR/urls-callbacks.txt"
  fi
  grep -Eiq 'webhook|callback|discord|telegram|slack|line|https?://' "$RAW_DIR/urls-callbacks.txt" && add_risk "MEDIUM" "URL or callback references detected" "Review integrations before shutdown."
  append_section "URL and Callback Scan" "$RAW_DIR/urls-callbacks.txt"
}

audit_apache() {
  if have apachectl; then
    run_raw apache-vhosts apachectl -S
  elif have apache2ctl; then
    run_raw apache-vhosts apache2ctl -S
  else
    write_raw_text apache-vhosts "apachectl/apache2ctl not found"
  fi
  grep -Eiq 'VirtualHost|namevhost' "$RAW_DIR/apache-vhosts.txt" && add_risk "MEDIUM" "Apache virtual hosts detected" "Review domains and traffic before shutdown."
  append_section "Apache" "$RAW_DIR/apache-vhosts.txt"
}

audit_nginx() {
  if have nginx; then
    run_raw nginx-config nginx -T
    grep -Ei 'server_name|listen|root|proxy_pass|fastcgi_pass' "$RAW_DIR/nginx-config.txt" >"$RAW_DIR/nginx-summary.txt" 2>/dev/null || true
  else
    write_raw_text nginx-config "nginx command not found"
    write_raw_text nginx-summary "nginx command not found"
  fi
  grep -Eiq 'server_name|listen' "$RAW_DIR/nginx-summary.txt" && add_risk "MEDIUM" "Nginx server blocks detected" "Review domains, proxy targets, and roots before shutdown."
  append_section "Nginx Summary" "$RAW_DIR/nginx-summary.txt"
}

audit_ssl() {
  if have certbot; then
    run_raw certbot-certificates certbot certificates
    grep -Ei 'Certificate Name|Domains:|Expiry Date:' "$RAW_DIR/certbot-certificates.txt" >"$RAW_DIR/ssl-summary.txt" 2>/dev/null || true
  else
    write_raw_text certbot-certificates "certbot command not found"
    write_raw_text ssl-summary "certbot command not found"
  fi
  grep -Eiq 'Domains:|Expiry Date:' "$RAW_DIR/ssl-summary.txt" && add_risk "MEDIUM" "SSL certificates detected" "Confirm certificates and renewals are migrated."
  append_section "SSL Certificates" "$RAW_DIR/ssl-summary.txt"
}

audit_logs() {
  : >"$RAW_DIR/access-log-sample.txt"
  for dir in /var/log/nginx /var/log/apache2 /var/log/httpd; do
    [ -d "$dir" ] || continue
    find "$dir" -type f \( -name '*access*.log' -o -name 'access_log' \) -print 2>/dev/null |
      while IFS= read -r f; do
        printf '\n==> %s <==\n' "$f"
        tail -n 100 "$f" 2>/dev/null
      done >>"$RAW_DIR/access-log-sample.txt"
  done
  awk '$1 ~ /^[0-9a-fA-F:.]+$/ {count[$1]++} END {for (ip in count) print count[ip], ip}' "$RAW_DIR/access-log-sample.txt" | sort -rn | head -n 20 >"$RAW_DIR/top-ips.txt"
  awk -F\" '/"[^"]+"/ {split($2,a," "); if (a[2] != "") count[a[2]]++} END {for (url in count) print count[url], url}' "$RAW_DIR/access-log-sample.txt" | sort -rn | head -n 20 >"$RAW_DIR/top-urls.txt"
  [ -s "$RAW_DIR/top-ips.txt" ] && add_risk "MEDIUM" "Recent access log activity found" "Review top IPs and URLs before shutdown."
  append_section "Recent Access Logs" "$RAW_DIR/access-log-sample.txt"
  append_section "Top IPs" "$RAW_DIR/top-ips.txt"
  append_section "Top URLs" "$RAW_DIR/top-urls.txt"
}

audit_cron() {
  : >"$RAW_DIR/cron.txt"
  crontab -l >>"$RAW_DIR/cron.txt" 2>&1 || true
  if [ "$(id -u 2>/dev/null)" = "0" ]; then
    crontab -u root -l >>"$RAW_DIR/cron.txt" 2>&1 || true
  elif have sudo; then
    sudo crontab -l >>"$RAW_DIR/cron.txt" 2>&1 || true
  fi
  find /etc -maxdepth 2 \( -name 'cron*' -o -path '/etc/cron.d/*' \) -print 2>/dev/null |
    while IFS= read -r f; do
      if [ -f "$f" ] && [ -r "$f" ]; then
        printf '\n==> %s <==\n' "$f"
        cat "$f"
      fi
    done >>"$RAW_DIR/cron.txt"
  grep -Ei 'php|curl|wget' "$RAW_DIR/cron.txt" >"$RAW_DIR/cron-flagged.txt" 2>/dev/null || true
  [ -s "$RAW_DIR/cron-flagged.txt" ] && add_risk "HIGH" "Cron jobs with php/curl/wget detected" "Scheduled jobs may call applications or callbacks."
  append_section "Cron Jobs" "$RAW_DIR/cron.txt"
  append_section "Flagged Cron Jobs" "$RAW_DIR/cron-flagged.txt"
}

audit_systemd() {
  if have systemctl; then
    run_raw systemd-running systemctl list-units --type=service --state=running --no-pager
    run_raw systemd-unit-files systemctl list-unit-files --type=service --no-pager
    grep -E '[[:space:]]enabled[[:space:]]' "$RAW_DIR/systemd-unit-files.txt" >"$RAW_DIR/systemd-enabled.txt" 2>/dev/null || true
  else
    write_raw_text systemd-running "systemctl command not found"
    write_raw_text systemd-unit-files "systemctl command not found"
    write_raw_text systemd-enabled "systemctl command not found"
  fi
  append_section "Systemd Running Services" "$RAW_DIR/systemd-running.txt"
  append_section "Systemd Enabled Services" "$RAW_DIR/systemd-enabled.txt"
}

audit_firewall() {
  : >"$RAW_DIR/firewall.txt"
  if have ufw; then
    { printf '$ ufw status verbose\n'; ufw status verbose 2>&1; printf '\n'; } >>"$RAW_DIR/firewall.txt"
  fi
  if have iptables; then
    { printf '$ iptables -S\n'; iptables -S 2>&1; printf '\n'; } >>"$RAW_DIR/firewall.txt"
  fi
  if have nft; then
    { printf '$ nft list ruleset\n'; nft list ruleset 2>&1; printf '\n'; } >>"$RAW_DIR/firewall.txt"
  fi
  [ -s "$RAW_DIR/firewall.txt" ] || write_raw_text firewall "ufw, iptables, and nft not found"
  grep -Eiq 'ALLOW|ACCEPT|dport|to any' "$RAW_DIR/firewall.txt" && add_risk "MEDIUM" "Firewall allow rules detected" "Review exposed ports and source ranges."
  append_section "Firewall" "$RAW_DIR/firewall.txt"
}

audit_special_services() {
  : >"$RAW_DIR/special-services.txt"
  ps aux 2>/dev/null | grep -Ei 'gitlab|minecraft|java.*server|grafana|prometheus|loki' | grep -v grep >>"$RAW_DIR/special-services.txt" || true
  grep -Ei 'external_url|gitlab_rails.*listen|nginx.*listen' /etc/gitlab/gitlab.rb 2>/dev/null | mask_sensitive >>"$RAW_DIR/special-services.txt" || true
  grep -Ei 'gitlab|minecraft|grafana|prometheus|loki' "$RAW_DIR/ports.txt" >>"$RAW_DIR/special-services.txt" 2>/dev/null || true
  grep -Eiq 'gitlab' "$RAW_DIR/special-services.txt" && add_risk "HIGH" "GitLab detected" "Confirm repositories, runners, webhooks, backups, and external URL."
  grep -Eiq 'minecraft|java.*server' "$RAW_DIR/special-services.txt" && add_risk "MEDIUM" "Minecraft server detected" "Confirm world backup and recent player activity."
  grep -Eiq 'grafana|prometheus|loki' "$RAW_DIR/special-services.txt" && add_risk "MEDIUM" "Grafana/Prometheus/Loki detected" "Confirm dashboards, alerts, and scrape targets are migrated."
  append_section "GitLab, Minecraft, and Monitoring" "$RAW_DIR/special-services.txt"
}

write_risks() {
  {
    printf '\n## Risk Scoring\n\n'
    if [ -s "$RISK_ITEMS" ]; then
      awk -F '\t' '{printf "- **%s**: %s - %s\n", $1, $2, $3}' "$RISK_ITEMS"
    else
      printf 'No obvious risks were detected from available read-only checks.\n'
    fi
  } >>"$MD"
}

write_checklist() {
  cat >>"$MD" <<'EOF'

## Migration Checklist

[ ] DNS transferred
[ ] SSL transferred
[ ] Access logs show no traffic
[ ] Docker backed up
[ ] Database backed up
[ ] Cron disabled
[ ] Callback confirmed
[ ] VM ready for shutdown
EOF
}

html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

write_html() {
  {
    cat <<'EOF'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>VM Audit Report</title>
<style>
body{font-family:Arial,Helvetica,sans-serif;line-height:1.5;margin:0;background:#f6f7f9;color:#20242a}
main{max-width:1100px;margin:0 auto;padding:32px 20px}
pre{white-space:pre-wrap;background:#111827;color:#e5e7eb;padding:16px;border-radius:6px;overflow:auto}
h1,h2{color:#111827} code{background:#e5e7eb;padding:1px 4px;border-radius:3px}
</style>
</head>
<body><main><pre>
EOF
    html_escape <"$MD"
    cat <<'EOF'
</pre></main></body></html>
EOF
  } >"$HTML"
}

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --output)
        shift
        [ "$#" -gt 0 ] || { say "--output requires a path"; exit 2; }
        REPORT_DIR="$1"
        RAW_DIR="$REPORT_DIR/raw"
        MD="$REPORT_DIR/report.md"
        HTML="$REPORT_DIR/report.html"
        RISK_ITEMS="$RAW_DIR/risks.tsv"
        ;;
      --version|-v)
        say "vm-audit $VERSION"
        exit 0
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      uninstall)
        if have uninstall.sh; then uninstall.sh; else rm -f /usr/local/bin/vm-audit; fi
        exit 0
        ;;
      *)
        usage
        exit 2
        ;;
    esac
    shift
  done

  progress "vm-audit $VERSION starting read-only audit."
  progress "Report directory: $REPORT_DIR"
  init_report
  run_step 1 14 "Collecting system information" audit_system
  run_step 2 14 "Scanning listening ports" audit_ports
  run_step 3 14 "Collecting Docker inventory" audit_docker
  run_step 4 14 "Scanning PHP websites" audit_php_sites
  run_step 5 14 "Scanning PHP configuration" audit_php_config
  run_step 6 14 "Scanning URLs and callbacks" audit_callbacks
  run_step 7 14 "Collecting Apache configuration" audit_apache
  run_step 8 14 "Collecting Nginx configuration" audit_nginx
  run_step 9 14 "Collecting SSL certificates" audit_ssl
  run_step 10 14 "Analyzing access logs" audit_logs
  run_step 11 14 "Collecting cron jobs" audit_cron
  run_step 12 14 "Collecting systemd services" audit_systemd
  run_step 13 14 "Collecting firewall rules" audit_firewall
  run_step 14 14 "Detecting special services" audit_special_services
  progress "Writing risk scoring and checklist..."
  write_risks
  write_checklist
  write_html
  say "Report written to $REPORT_DIR/report.md"
  say "HTML report written to $REPORT_DIR/report.html"
}

main "$@"
