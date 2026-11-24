#!/bin/sh
# Encrypt ./config.json and push it to the gist as config.enc.
# Needs ./.env with GIST_ID, GITHUB_TOKEN (gist scope) and KEY.
set -eu
cd "$(dirname "$0")"
. ./.env
export KEY
SRC=config.json

if command -v sing-box >/dev/null; then sing-box check -c "$SRC"; fi

ENC=$(openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 -salt -a -A -pass env:KEY -in "$SRC")
printf '{"files":{"config.enc":{"content":"%s"}}}' "$ENC" |
  curl -fsS -X PATCH -o /dev/null --data @- \
    -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/gists/$GIST_ID"

echo "published, config_sha=$(sha256sum <"$SRC" | cut -c1-12)"
