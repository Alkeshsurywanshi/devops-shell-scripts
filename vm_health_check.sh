#!/usr/bin/env bash
# Report basic Linux VM health: load, memory, and root filesystem usage.
# Usage: chmod +x vm_health_check.sh && ./vm_health_check.sh
# Optional thresholds: CPU_WARN=1.0, MEM_WARN=80, DISK_WARN=80

set -u

CPU_WARN=${CPU_WARN:-1.0}       # 1-minute load per CPU core
MEM_WARN=${MEM_WARN:-80}        # percentage used
DISK_WARN=${DISK_WARN:-80}      # percentage used on /

status=0

pass() { printf '[OK]      %s\n' "$1"; }
warn() { printf '[WARNING] %s\n' "$1"; status=1; }
fail() { printf '[ERROR]   %s\n' "$1"; status=1; }

printf 'Virtual Machine Health Check\n'
printf '============================\n'
printf 'Host: %s\n' "$(hostname 2>/dev/null || printf 'unknown')"
printf 'Date: %s\n\n' "$(date 2>/dev/null || printf 'unknown')"

# Uptime/load average. Linux provides load average in /proc/loadavg.
if [[ -r /proc/loadavg ]]; then
  read -r load1 _ < /proc/loadavg
  cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')
  if awk -v load="$load1" -v cores="$cores" -v limit="$CPU_WARN" \
    'BEGIN { exit !(cores > 0 && load / cores > limit) }'; then
    warn "CPU load: $load1 (1-minute load per core exceeds $CPU_WARN)"
  else
    pass "CPU load: $load1 (1-minute load; $cores CPU core(s))"
  fi
else
  warn 'CPU load: /proc/loadavg unavailable; skipped'
fi

# Prefer `free`'s available-memory field, which accounts for reclaimable cache.
if command -v free >/dev/null 2>&1; then
  mem_pct=$(free -m | awk '/^Mem:/ { if ($2 > 0) printf "%d", ($2 - $7) * 100 / $2 }')
  if [[ "$mem_pct" =~ ^[0-9]+$ ]]; then
    if (( mem_pct >= MEM_WARN )); then
      warn "Memory usage: ${mem_pct}% (warning threshold: ${MEM_WARN}%)"
    else
      pass "Memory usage: ${mem_pct}% (warning threshold: ${MEM_WARN}%)"
    fi
  else
    warn 'Memory usage: could not read memory statistics; skipped'
  fi
elif [[ -r /proc/meminfo ]]; then
  mem_pct=$(awk '
    /^MemTotal:/ { total=$2 }
    /^MemAvailable:/ { available=$2 }
    END { if (total > 0) printf "%d", (total - available) * 100 / total }
  ' /proc/meminfo)
  if [[ "$mem_pct" =~ ^[0-9]+$ ]]; then
    if (( mem_pct >= MEM_WARN )); then
      warn "Memory usage: ${mem_pct}% (warning threshold: ${MEM_WARN}%)"
    else
      pass "Memory usage: ${mem_pct}% (warning threshold: ${MEM_WARN}%)"
    fi
  else
    warn 'Memory usage: could not read /proc/meminfo; skipped'
  fi
else
  warn 'Memory usage: neither free nor /proc/meminfo is available; skipped'
fi

# Check the root filesystem; df -P keeps output to one line per filesystem.
if command -v df >/dev/null 2>&1; then
  disk_pct=$(df -P / 2>/dev/null | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }')
  if [[ "$disk_pct" =~ ^[0-9]+$ ]]; then
    if (( disk_pct >= DISK_WARN )); then
      warn "Root filesystem usage: ${disk_pct}% (warning threshold: ${DISK_WARN}%)"
    else
      pass "Root filesystem usage: ${disk_pct}% (warning threshold: ${DISK_WARN}%)"
    fi
  else
    warn 'Root filesystem usage: could not read df output; skipped'
  fi
else
  fail 'df command not found; cannot check disk usage'
fi

printf '\n'
if (( status == 0 )); then
  printf 'Overall result: HEALTHY\n'
else
  printf 'Overall result: ATTENTION REQUIRED\n'
fi

exit "$status"
