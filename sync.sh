#!/bin/sh
# Fetch encrypted sing-box config from gist, verify, apply, report to CSV in a repo.
# Usage: sync.sh [conf]   (default /etc/sing-box-sync.conf)
set -u
umask 077
. "${1:-/etc/sing-box-sync.conf}"
: "${GIST_URL:?}" "${KEY:?}"
export KEY
TARGET=${TARGET:-/etc/sing-box/config.json}
RESTART=${RESTART:-/etc/init.d/sing-box restart}
DEVICE=${DEVICE:-$(cat /proc/sys/kernel/hostname)}
REPORT_DIR=${REPORT_DIR:-reports}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
status=fail hash= err=

log() { logger -t sing-box-sync "$*" 2>/dev/null; echo "$*"; }

run() {
  curl -fsSL --retry 3 -o "$TMP/enc" "$GIST_URL" || { err=download; return; }
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 -a -A -pass env:KEY \
    -in "$TMP/enc" -out "$TMP/new.json" 2>/dev/null || { err=decrypt; return; }
  hash=$(sha256sum <"$TMP/new.json" | cut -c1-12)
  # check output may contain config details: syslog only, not the public CSV
  sing-box check -c "$TMP/new.json" >"$TMP/chk" 2>&1 || { log "$(cat "$TMP/chk")"; err=check; return; }
  if cmp -s "$TMP/new.json" "$TARGET"; then status=unchanged; return; fi

  [ -f "$TARGET" ] && cp "$TARGET" "$TARGET.bak"
  cp "$TMP/new.json" "$TARGET"
  if sh -c "$RESTART" >/dev/null 2>&1 && sleep 5 && pidof sing-box >/dev/null; then
    status=updated; return
  fi
  [ -f "$TARGET.bak" ] && cp "$TARGET.bak" "$TARGET" && sh -c "$RESTART" >/dev/null 2>&1
  status=rollback err=restart
}

report() {
  [ -n "${REPORT_REPO:-}" ] || return 0
  api="https://api.github.com/repos/$REPORT_REPO/contents/$REPORT_DIR/${now%%-*}.csv"
  auth="Authorization: Bearer $REPORT_TOKEN"
  for i in 1 2 3; do
    # read current year's file (sha + content), append line, write back; retry on conflict
    code=$(curl -sS -H "$auth" -o "$TMP/r.json" -w '%{http_code}' "$api")
    : >"$TMP/r.csv"
    shaf=
    if [ "$code" = 200 ]; then
      shaf=",\"sha\":\"$(grep -o '"sha": *"[0-9a-f]*"' "$TMP/r.json" | head -n1 | grep -o '[0-9a-f]\{40\}')\""
      size=$(grep -o '"size": *[0-9]*' "$TMP/r.json" | head -n1 | grep -o '[0-9]*$')
      grep -o '"content": *"[^"]*"' "$TMP/r.json" | head -n1 |
        sed 's/^"content": *"//; s/"$//; s/\\n//g' | openssl base64 -d -A >"$TMP/r.csv"
      # API returns no content for files >1MB: never overwrite history with one line
      [ -s "$TMP/r.csv" ] || [ "$size" = 0 ] || { log "report: no content from $api"; return 1; }
    elif [ "$code" != 404 ]; then
      sleep $((i * 10)); continue
    fi
    if [ -s "$TMP/r.csv" ]; then
      [ -n "$(tail -c1 "$TMP/r.csv")" ] && echo >>"$TMP/r.csv"
    else
      echo "time,device,status,config_sha,error" >"$TMP/r.csv"
    fi
    echo "$1" >>"$TMP/r.csv"
    printf '{"message":"report %s %s","content":"%s"%s}' \
      "$DEVICE" "$status" "$(openssl base64 -A -in "$TMP/r.csv")" "$shaf" >"$TMP/put.json"
    curl -fsS -X PUT -H "$auth" -o /dev/null --data @"$TMP/put.json" "$api" && return 0
    sleep $((i * 10))
  done
  return 1
}

run
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
line="$now,$DEVICE,$status,$hash,$err"
log "$line"
report "$line" || log "report failed"
[ "$status" = updated ] || [ "$status" = unchanged ]
