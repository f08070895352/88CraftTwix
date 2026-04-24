# n8n 実装手順書（共通セットアップ）

01〜04 の全ワークフローを動かすための前提セットアップです。各ワークフロー個別の使い方は `docs/01_*.md` 〜 `docs/04_*.md` を参照してください。

---

## 1. 必要なもの

| 項目 | 用途 | 備考 |
|---|---|---|
| n8n 本体 | ワークフロー実行 | Cloud / Self-host どちらでもOK。バージョン 1.50+ 推奨 |
| Google アカウント | Sheets 書き込み | OAuth2 を使う |
| X (Twitter) Developer アカウント | 投稿・DM・検索 | Basic プラン以上。Free プランでは DM / search が使えません |
| Anthropic API キー | Claude 呼び出し（03, 04） | console.anthropic.com で発行 |

---

## 2. n8n Credentials の作成

n8n 左メニューの **Credentials → New** から以下3つを作成します。

### 2.1 Google Sheets OAuth（ID: `GSHEETS_CRED`）
1. Credential type: **Google Sheets OAuth2 API**
2. Google Cloud Console で OAuth クライアントを作り Client ID / Secret を貼り付け
3. Redirect URL は n8n が表示するものをそのまま GCP に登録
4. Scope: `spreadsheets`, `drive.file`
5. **Connect** を押して Google でアクセス許可
6. 完了後、Credential 名を `Google Sheets OAuth` に（n8n 内での参照名）

### 2.2 X/Twitter OAuth2（ID: `TWITTER_CRED`）
1. Credential type: **Twitter OAuth2 API**
2. X Developer Portal → Project → App → Keys and tokens で OAuth 2.0 Client ID / Secret を発行
3. App の User authentication settings で以下を設定:
   - Type: **OAuth 2.0**
   - App permissions: **Read and write and Direct message**
   - Callback URL: n8n の表示するURL
   - Website URL: 任意
4. Scope: `tweet.read tweet.write users.read dm.read dm.write offline.access`
5. **Connect** → X で承認
6. Credential 名を `X/Twitter OAuth2` に

### 2.3 Anthropic API（ID: `ANTHROPIC_CRED`）
1. Credential type: **Anthropic API**
2. API Key に console.anthropic.com のキーを貼り付け
3. Credential 名を `Anthropic API` に

> ワークフロー JSON 内のノードは `id: "GSHEETS_CRED"` 等で参照しています。インポート直後に各ノードを開いて、自分で作った Credential を **選び直してください**（名前が一致していれば自動で紐付くこともあります）。

---

## 3. Google Sheets の準備

同じスプレッドシートの中に **5 シート** を作ります（別ファイルでもOK、その場合は env を分ける）。

### 3.1 `campaigns`（キャンペーン管理）
| campaign_id | prize | hashtag | keyword | deadline | status | tweet_id | posted_at |
|---|---|---|---|---|---|---|---|
| cmp_20260501 | 副業スタートガイドPDF | #副業ノウハウプレゼント | 参加 | 5/3 23:59まで | queued | | |

### 3.2 `applicants`（応募者集計）
| campaign_id | tweet_id | author_id | username | name | text | created_at | status | drawn_at | dm_sent_at |
|---|---|---|---|---|---|---|---|---|---|

### 3.3 `autoreplies`（AI自動返信ログ）
| campaign_id | reply_id | author_id | username | original_text | generated_reply | posted_at |
|---|---|---|---|---|---|---|

### 3.4 `persona`（アカウント世界観、1行だけ）
| handle | worldview | tone | target | ng_words | voice_samples |
|---|---|---|---|---|---|
| @your_handle | 会社に縛られず通勤中にコツコツ育てる副業を発信 | フレンドリーで断定的、絵文字控えめ、箇条書き多め | 副業を始めたい20-30代の会社員 | 絶対稼げる / 誰でも月100万 | （過去バズ投稿を2〜3件改行で貼る） |

### 3.5 `posts`（仮説→ポスト生成ログ）
| created_at | category | hypothesis | variant_index | hook | post_text | reason | research_json | posted | tweet_id | posted_at |
|---|---|---|---|---|---|---|---|---|---|---|

> **ヘッダ行の文字列は JSON 内の列名と完全一致**させてください。全角/半角スペースの違いで upsert が失敗します。

---

## 4. 環境変数の設定

n8n の **Settings → Environment Variables**（Self-host の場合は `.env`）に追加:

| 変数名 | 値の例 | 用途 |
|---|---|---|
| `GSHEET_CAMPAIGNS_ID` | `campaigns` | 3.1 のシート名 |
| `GSHEET_APPLICANTS_ID` | `applicants` | 3.2 のシート名 |
| `GSHEET_AUTOREPLIES_ID` | `autoreplies` | 3.3 のシート名 |
| `GSHEET_PERSONA_ID` | `persona` | 3.4 のシート名 |
| `GSHEET_POSTS_ID` | `posts` | 3.5 のシート名 |
| `X_BOT_USER_ID` | `1234567890` | 自分のXアカウントの数値ID（[tweeterid.com](https://tweeterid.com) などで取得） |

> Google Sheets ノードは `Document` と `Sheet name` を分けて指定するUIのバージョンもあります。その場合は Document 側で対象ブックを選び、Sheet name に上記 env を入れる構成に差し替えてください。

---

## 5. インポート手順

1. n8n で **Workflows → Import from File**
2. `workflows/01_campaign_announce_and_collect.json` を選択
3. 各ノードを開いて Credentials をプルダウンから紐付け直す
4. 保存 → **Inactive** のまま動作確認（後述の個別マニュアル参照）
5. 02, 03, 04 も同様にインポート

---

## 6. 最小動作確認（スモークテスト）

全部アクティベートする前に、以下の順で1件ずつ手で流します。

1. **01 を Manual Execute**: `campaigns` に queued 行を1つ入れ、上段の `Daily 19:00 JST` を右クリック → Execute Node で投稿が飛ぶか確認（本番前は X API 側のテストアカウント推奨）
2. **01 下段をテスト**: `running` 行があることを確認し、`Every 10 min` を Execute Node。`applicants` に行が入るか
3. **02 を実行**: Manual Trigger → フォームを開いて `dry_run=true` で抽選 → `applicants` に `winner` がつくか
4. **03 を Execute Node**: 返信は `Post Reply` を一旦 **無効化**し、`autoreplies` に想定の文面が溜まるか先に確認
5. **04 を実行**: フォームに仮説を入力、`dry_run=true` で `posts` に3案入るか

すべて緑になったらそれぞれ **Active** に切り替え。

---

## 7. トラブルシュート早見

| 症状 | 原因 | 対処 |
|---|---|---|
| Sheets ノードで `Unable to find column` | ヘッダ名不一致 | 3章のヘッダを全角/半角そのままでコピー |
| X 投稿が 403 | App 権限が Read only | Developer Portal で Read and write and DM に変更 → トークン再発行 |
| X search が 401/403 | Free プラン | Basic 以上に変更 |
| DM が 403 (code 349) | 相手が未フォロー or DM拒否 | 告知文に「フォロー必須」明記 |
| Claude ノードで 401 | API キー失効 | Credential を更新 |
| `conversation_id` 検索で空 | Basic プランは `conversation_id` 使用可、Free は不可 | プラン確認 |
| Upsert が重複行を作る | `matchingColumns` がヘッダに存在しない | `tweet_id` 列があるか確認 |

---

## 8. セキュリティと運用メモ

- API キー・トークンは Credentials にのみ置き、ワークフロー JSON にハードコードしない（現状のJSONにも一切入っていません）
- 03 の自動返信は X の自動化ポリシーに従い、1日 **数十件以下**に抑える運用が安全（現状は5分間隔 + 15分窓 + Wait 30秒で緩めに設定）
- 04 は最初は全件 `dry_run=true` にして、週に1〜2回人間が選んで投稿するハイブリッド運用が現実的
- 抽選ログ（`applicants` の winner 行と `drawn_at`）は景表法の記録として半年程度保管推奨
