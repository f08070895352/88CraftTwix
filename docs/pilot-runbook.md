# X API Pilot 実行 Runbook

**目的**: 本番投入前に Basic tier で実レート・実403を測って、ワークフローのcron間隔とリトライ戦略を確定させる。

## 前提

- X Developer Portal で Basic tier ($100/月) 以上を契約済み
- OAuth2 ユーザ認証のトークン (`X_USER_TOKEN`) が取得済み
  - 必要スコープ: `tweet.read users.read dm.read dm.write offline.access`
- Bearer Token (`X_BEARER_TOKEN`) は read-only には使えるがDMには不可

## Phase 1: レート制限の実測 (10分)

```bash
export X_USER_ID=1234567890          # 自分のID
export X_USER_TOKEN=xxxxxxxxxxxxxx   # OAuth2 ユーザトークン

./scripts/pilot-x-api.sh
```

**見るもの**:

| エンドポイント | Basic tier公称 | 実測で確認 |
|---|---|---|
| `GET /users/:id/mentions` | 10 req / 15min | remaining が何回目に0になるか |
| `GET /users/:id/followers` | 15 req / 15min | 同上 |
| `GET /users/me` | 25 req / 24h | これだけ日次枠なので注意 |

**判断**:
- mentions が 5分Cron (= 15分で3回) で余裕あり → そのまま
- 429 発生 → `workflows/reply-to-dm-to-sales.json` の Schedule Trigger を 10分/15分 に伸ばす

## Phase 2: DM送信の動作確認 (15分)

> **警告**: ここから先は実際にDMが飛びます。テスト用のセカンダリアカウントから自分の本アカウントへリプを付けて検証すること。

### 2-1. 自分のアカウントに「test reply」を手動で投稿

本アカウント (X_USER_ID) にテストアカウントからリプライ:
> 「これ気になります！値段いくらですか？」

### 2-2. n8n ワークフローを手動Execute

n8n UI で `Reply → DM → Sales Automation` を開き、`Execute Workflow` をクリック。
各ノードの実行結果を確認:

1. **リプライ取得** → テストリプが `data` に入っているか
2. **AI分類・返信生成** → `lead_score >= 40` になっているか、`suggested_reply` が商品名を踏まえているか
3. **自動リプライ投稿** → HTTP 201, `data.id` 返却
4. **DM送信（特典LP付き）** → HTTP 201 or 403 を記録

### 2-3. 403パターンの収集

DM 403の原因TOP3を把握:

| エラーコード | 原因 | 対処 |
|---|---|---|
| `403 - You are not allowed to message this user` | 受信者がDMを「全員から受け取る」にしていない | `DM feasibility precheck` ノードで事前除外 |
| `403 - This user blocked you` | ブロック済み | 同上 |
| `403 - Not permitted to access DM endpoints` | アプリのDMスコープが未承認 | Developer Portal でアプリ設定を確認 |

各403を Supabase `leads.stage='dm_failed'` に入り、`#ops-alerts` へ通知されているか確認。

## Phase 3: 24時間モニタリング

```bash
# 1日寝かせて監視
# Slack #sales-alerts と #ops-alerts に通知が届くか
# Supabase に leads が積まれているか
```

翌朝 `Daily KPI Report` の Slack投稿で:
- `DM送信 vs 購入` の比率
- `dm_failed` の割合（> 50%なら事前チェックを強化）
- `avg_score` の分布

## Phase 4: 本番投入判断

以下が全て ✅ なら Activate:

- [ ] Phase 1: 429 が 24h で 0 回
- [ ] Phase 2: DM成功率 > 50%、403は全て `dm_failed` で記録
- [ ] Phase 3: エラーログに PII やトークン流出なし
- [ ] `processed_replies` が UNIQUE違反なく蓄積している
- [ ] ErrorWorkflow が最低1回発火して Slackに飛んでいる (意図的にSupabaseをDownさせる等)

## ロールバック手順

```
# n8n UI で全ワークフローを Deactivate
# Supabase の leads テーブルから誤送信分を DELETE
# X 側で自動投稿したリプライを 1件ずつ削除 (API: DELETE /2/tweets/:id)
```
