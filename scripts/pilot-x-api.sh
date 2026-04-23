#!/usr/bin/env bash
# X API の pilot実行スクリプト
# - /mentions と /users のレート制限ヘッダを記録
# - DM送信は実施しない（read-onlyチェック）
# - 本番投入前にこれで実レートを測る
#
# 必要: jq, curl
# 環境変数: X_BEARER_TOKEN (v2 App-only) または X_USER_TOKEN (OAuth2 ユーザ)
#          X_USER_ID (自分のuser id)

set -euo pipefail

: "${X_USER_ID:?set X_USER_ID}"
TOKEN="${X_USER_TOKEN:-${X_BEARER_TOKEN:-}}"
: "${TOKEN:?set X_USER_TOKEN (preferred) or X_BEARER_TOKEN}"

LOG_DIR="${LOG_DIR:-/tmp/x-pilot-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$LOG_DIR"
echo "Logging to: $LOG_DIR"

probe() {
  local label="$1"
  local url="$2"
  local out="$LOG_DIR/$label.json"
  local hdr="$LOG_DIR/$label.headers"
  echo ""
  echo "=== $label ==="
  echo "GET $url"
  local status
  status=$(curl -sS -o "$out" -D "$hdr" -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" "$url")
  echo "HTTP $status"
  local limit remaining reset
  limit=$(grep -i '^x-rate-limit-limit:' "$hdr" | awk '{print $2}' | tr -d '\r')
  remaining=$(grep -i '^x-rate-limit-remaining:' "$hdr" | awk '{print $2}' | tr -d '\r')
  reset=$(grep -i '^x-rate-limit-reset:' "$hdr" | awk '{print $2}' | tr -d '\r')
  echo "rate: ${remaining:-?}/${limit:-?} remaining (reset epoch: ${reset:-?})"
  if [[ "$status" != "200" ]]; then
    echo "-- body --"
    cat "$out"
  else
    echo "items: $(jq '.data | length // 0' "$out")"
  fi
}

# 1. メンション取得 (n8n の "リプライ取得" と同じクエリ)
MENTIONS_URL="https://api.twitter.com/2/users/${X_USER_ID}/mentions?max_results=50&tweet.fields=author_id,created_at,conversation_id,referenced_tweets,text&expansions=author_id&user.fields=username,public_metrics,verified"
probe "mentions" "$MENTIONS_URL"

# 2. フォロワー取得 (new-follower workflow と同じクエリ)
FOLLOWERS_URL="https://api.twitter.com/2/users/${X_USER_ID}/followers?max_results=200&user.fields=username,name,description,created_at,public_metrics,verified,protected"
probe "followers" "$FOLLOWERS_URL"

# 3. 自分のプロフィール取得 (auth動作確認用)
ME_URL="https://api.twitter.com/2/users/me"
probe "me" "$ME_URL"

# 4. 短時間連続コールでレート消費を観測 (3回)
for i in 1 2 3; do
  probe "mentions-burst-$i" "$MENTIONS_URL"
  sleep 1
done

echo ""
echo "=== 所感の取り方 ==="
echo "- mentions の remaining が 15分窓で何回目に 0 になるかを確認"
echo "- 429 が返ったら x-rate-limit-reset を見て次の窓を待つ"
echo "- Basic tier で mentions = 10 req / 15min (2025年時点)"
echo "- 5分Cron運用なら 15分窓で3回消費 → 余力7。OK"
echo "- 429が頻発するなら Cron を10分間隔へ"
