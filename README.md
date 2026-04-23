# n8n 完全自動化: リプ → DM → 販売

X (旧Twitter) への**リプライ取得 → AI分類 → 自動リプ → DM送信 → 購入トラッキング → フォローアップ**までを
n8n 1本のワークフローで回すためのテンプレートです。

## 全体フロー

```
[5分ごとCron]
    ↓
リプライ取得 (X API v2 /mentions)
    ↓
Supabaseで重複除外
    ↓
OpenAI で intent 判定 & lead_score 付与 & 返信文生成
    ↓
スコア >= 40 なら ──┐
    ↓              │
自動リプライ投稿    │
    ↓              │
30秒待機 → DM送信（特典LP付き）
    ↓
leads テーブルに保存 (stage=dm_sent)
    ↓
Slack通知

[Stripe Webhook]
    ↓
checkout.session.completed を受信
    ↓
leads を stage=purchased に更新 + お礼DM

[24hごとCron]
    ↓
stage=dm_sent かつ 24h経過 & followup_count<2 のリードへ
    ↓
フォローアップDM (クーポンLP)
```

## セットアップ

### 1. n8n を用意

- セルフホスト: `docker run -it --rm -p 5678:5678 n8nio/n8n`
- または n8n Cloud

### 2. 依存サービスの準備

| サービス | 役割 | 必要なスコープ／キー |
|---|---|---|
| X Developer | リプ監視 / 自動リプ / DM送信 | OAuth2 ユーザ認証で `tweet.read tweet.write users.read dm.read dm.write offline.access` |
| OpenAI | インテント分類 & 返信生成 | API Key (gpt-4o-mini想定) |
| Supabase | リード & 重複テーブル | Project URL + Service Role Key |
| Stripe | 決済Webhook | `checkout.session.completed` を n8n の Webhook URL へ |
| Slack | 営業通知 | Bot Token (`chat:write`) |

### 3. Supabase スキーマを流す

```bash
psql "$SUPABASE_DB_URL" -f supabase/schema.sql
```

### 4. n8n Credentials を登録

n8n UI の **Credentials** に次を作成:

- `Twitter OAuth2 API` → 上記スコープでOAuth完了させる
- `Supabase API` → URL + Service Role Key
- `OpenAI API` → OPENAI_API_KEY
- `Slack API` → Bot Token

### 5. 環境変数を設定

n8n の **Settings → Environment Variables** または `.env` に:

```bash
X_USER_ID=1234567890
CHECKOUT_BASE_URL=https://example.com/checkout
```

### 6. ワークフローをインポート

`workflows/reply-to-dm-to-sales.json` を n8n の **Workflows → Import from File** で取り込み、
各ノードの Credentials を選択し **Activate** を押す。

### 7. Stripe Webhook を接続

n8n 側で有効化された `/webhook/stripe-checkout-completed` の URL を Stripe Dashboard → Developers → Webhooks に登録。イベントは `checkout.session.completed` を選択。

Checkout Session 作成時に `client_reference_id` に X の `author_id` を必ず入れること
（これでリードとの紐付けが行われます）。

## 同梱ワークフロー

| ファイル | 役割 |
|---|---|
| `workflows/reply-to-dm-to-sales.json` | メインフロー（リプ取得→AI判定→自動リプ→DM→保存→フォロー） |
| `workflows/stripe-checkout-session-creator.json` | `GET /checkout?ref=<author_id>` を受けて Stripe Checkout Session を作り 302 リダイレクト |
| `workflows/error-handler.json` | Error Trigger → Slack 通報 + `error_log` テーブルへ保存（各ワークフローの **Settings → Error Workflow** でこれを指定） |
| `workflows/daily-kpi-report.json` | 毎朝9時に直近24hの DM数 / CVR / 売上 / 平均リードスコアを Slack 投稿 |
| `workflows/new-follower-welcome-dm.json` | 15分ごとに `/users/:id/followers` を取得 → `known_followers` テーブルと差分検知 → 新規のみBot除外フィルタ後にウェルカムDM送信 |

## テスト素材

- `fixtures/sample-mention.json` — X API `/mentions` レスポンスの模擬（3件：質問 / スパム / 見込み客）
- `fixtures/sample-stripe-webhook.json` — `checkout.session.completed` の模擬ペイロード
- `config/product-context.json` — AIプロンプトに差し込む商品情報 & トーン設定

`AI分類・返信生成` ノードの system プロンプト末尾に `config/product-context.json` の内容を差し込むことで、
商品名・価格・FAQを踏まえた返信になります（Set ノード経由で `{{ $json.product_context }}` として渡す設計）。

## 堅牢化済みの挙動

- **AI返信は商品コンテキストに基づく**: `商品コンテキスト` Setノードに `config/product-context.json` の内容を埋め込んであります。UI で直接編集 OK。AI は名前・価格・FAQをここから引用し、創作しないように指示されています。
- **DM送信失敗を自動検知**: `DM送信（特典LP付き）` は 3回リトライ → 最終失敗時は `leads.stage=dm_failed` として保存し、`#ops-alerts` へ Slack 通報。ブロック/受信拒否ユーザでワークフロー全体が止まりません。
- **Stripe Webhook の署名検証**: `Stripe署名検証` Code ノードが `Stripe-Signature` ヘッダを HMAC-SHA256 で検証 + 5分以内のリプレイ対策。検証失敗時は throw してErrorWorkflowへ。
  - セルフホストn8nでは `NODE_FUNCTION_ALLOW_BUILTIN=crypto` を環境変数に設定してください（Docker: `-e NODE_FUNCTION_ALLOW_BUILTIN=crypto`）。
  - `.env` に `STRIPE_WEBHOOK_SECRET=whsec_...` を追加。

## カスタマイズポイント

- **lead_score のしきい値**: `見込み客判定` ノードで `>= 40` を変更
- **AIモデル**: `AI分類・返信生成` を `gpt-4o` や Claude へ差し替え可
- **DM本文 / フォロー回数**: それぞれのHTTPノード `jsonBody` を編集
- **プラットフォーム拡張**: X部分を Instagram / TikTok に差し替えても同じ骨格で動きます

## 新規フォロワーDMの初回ブートストラップ

`new-follower-welcome-dm.json` は「`known_followers` に居ない人 = 新規」として扱います。
**初回アクティベート前に、既存フォロワー全員をテーブルへ流し込んでおく**ことで、古いフォロワーへの誤DMを防げます。

```bash
# 1. ワークフローを一時的に "ウェルカムDM送信" と "Slack通知" ノードだけ無効化してから Execute Workflow
# 2. 1回の実行で known_followers に全件入るので、ノードを再度有効化して Activate
```

もしくは SQL で直接シード:

```sql
-- 既存フォロワーIDをCSVで用意して一括INSERT
copy known_followers (follower_id, dm_sent) from '/path/to/followers.csv' csv;
```

## 本番投入前のチェックリスト

以下は1度走らせるだけで済む運用前ハードニング:

1. **ワークフローJSONの正規化** — n8n でインポートしないと typeVersion や parameter shape にズレがあるかどうか最終確認できない。ローカルに n8n を入れて:
   ```bash
   ./scripts/normalize-workflows.sh
   git diff workflows/
   ```
   差分が出たらそれが n8n 公式の形。commit して上書き。
2. **静的リント** — CI に入れて壊れたJSONを早期検知:
   ```bash
   node ./scripts/lint-workflows.mjs
   ```
3. **X API pilot** — 本番トークンでレート・DM成否を実測:
   ```bash
   X_USER_ID=... X_USER_TOKEN=... ./scripts/pilot-x-api.sh
   ```
   手順は `docs/pilot-runbook.md` 参照。
4. **Supabase RLS** — schema.sql を流した後に必ず:
   ```bash
   psql "$SUPABASE_DB_URL" -v n8n_writer_password="$(openssl rand -hex 24)" \
     -f supabase/rls.sql
   ```
   n8n のクレデンシャルには `service_role` ではなく `n8n_writer` の JWT を設定する。

## 運用上の注意

- X APIのDM送信は **相手が受信可能設定** でないと弾かれます。429/403はリトライキューへ。
- X APIのレート制限に合わせて Cron 間隔は5分以上を推奨。
- 自動リプは規約違反にならない頻度・内容に必ず調整してください。
- `processed_replies` は `tweet_id` UNIQUE なので、冪等性が保たれます。
