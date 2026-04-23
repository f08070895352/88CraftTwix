#!/usr/bin/env bash
# n8n CLI を使って workflows/*.json を import → export することで
# node typeVersion / parameter shape を n8n 本体が受け付ける形に正規化する。
#
# 前提: npm i -g n8n （または docker run n8nio/n8n）でn8nがローカルに入っていること
# 使い方:  ./scripts/normalize-workflows.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IN="$ROOT/workflows"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! command -v n8n >/dev/null 2>&1; then
  echo "n8n CLI が見つかりません。 npm i -g n8n でインストールしてください。" >&2
  exit 1
fi

echo "[1/3] 既存workflowを n8n DB にimport"
for f in "$IN"/*.json; do
  echo "  - $(basename "$f")"
  n8n import:workflow --input="$f" >/dev/null
done

echo "[2/3] n8n DB から再export (正規化済み)"
n8n export:workflow --all --output="$TMP" --pretty >/dev/null

echo "[3/3] workflows/ を上書き"
for exported in "$TMP"/*.json; do
  name="$(jq -r '.name' "$exported")"
  target="$IN/$(echo "$name" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-').json"
  # ファイル名が一致する既存workflowがあればそれを上書き、無ければ名前ベースで作成
  match="$(grep -l "\"name\": \"$name\"" "$IN"/*.json || true)"
  if [[ -n "$match" ]]; then
    cp "$exported" "$match"
    echo "  ✓ $(basename "$match")"
  else
    cp "$exported" "$target"
    echo "  + $(basename "$target")"
  fi
done

echo "正規化完了。 git diff workflows/ で変更を確認してください。"
