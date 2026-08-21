#!/usr/bin/env bash
# Cloudflare の API トークンを GitHub Secrets へ登録し、権限まで検証する。
#
# 前提: Cloudflare ダッシュボードで Custom Token を作成し、
#       表示直後のコピーボタンを押してクリップボードに入れてあること。
#       トークンは一度しか表示されないので、押し損ねたら作り直す。
#
# 使い方: ./setup-cf-secrets.sh <owner>/<repo> <ACCOUNT_ID>
#
# トークンの値は一度も標準出力に出さない。出すのは長さ・形の真偽・API の応答だけ。
set -euo pipefail

REPO="${1:?usage: setup-cf-secrets.sh <owner>/<repo> <ACCOUNT_ID>}"
ACC="${2:?usage: setup-cf-secrets.sh <owner>/<repo> <ACCOUNT_ID>}"

TOKEN=$(pbpaste)

echo "--- clipboard shape ---"
printf 'length=%s\n' "${#TOKEN}"
if printf '%s' "$TOKEN" | grep -Eq '^(cfut_[A-Za-z0-9_.-]+|[A-Za-z0-9_-]{40})$'; then
  echo "shape=ok"
else
  echo "shape=unexpected — コピーボタンを押し間違えている可能性がある" >&2
  exit 1
fi

echo "--- register secrets ---"
printf '%s' "$TOKEN" | gh secret set CLOUDFLARE_API_TOKEN -R "$REPO"
printf '%s' "$ACC"   | gh secret set CLOUDFLARE_ACCOUNT_ID -R "$REPO"
gh secret list -R "$REPO"

echo "--- token verify ---"
curl -sS "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $TOKEN" \
  | sed -E 's/"id":"[^"]*"/"id":"<redacted>"/g'
echo

echo "--- pages permission (403 なら権限スコープが違う) ---"
OUT=$(mktemp)
curl -sS -o "$OUT" -w 'http_status=%{http_code}\n' \
  "https://api.cloudflare.com/client/v4/accounts/$ACC/pages/projects" \
  -H "Authorization: Bearer $TOKEN"
python3 -c "
import json,sys
d=json.load(open('$OUT'))
print('success=',d['success'])
print('errors=',d['errors'])
print('project_count=',len(d.get('result') or []))
sys.exit(0 if d['success'] else 1)
"
rm -f "$OUT"

printf '' | pbcopy
echo "--- clipboard cleared ---"
