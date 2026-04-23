# Google Sheets スキーマ

3つのワークフローが参照する Sheets の列定義です。n8n の Credentials で `GSHEETS_CRED` と `TWITTER_CRED`、`ANTHROPIC_CRED` を作成し、以下の環境変数を設定してください。

## 環境変数

| 変数名 | 用途 |
|---|---|
| `GSHEET_CAMPAIGNS_ID` | キャンペーン管理シートの gid または名前 |
| `GSHEET_APPLICANTS_ID` | 応募者集計シートの gid または名前 |
| `GSHEET_AUTOREPLIES_ID` | AI自動返信ログシートの gid または名前 |
| `GSHEET_PERSONA_ID` | アカウント世界観シートの gid または名前 |
| `GSHEET_POSTS_ID` | 仮説→ポスト生成ログシートの gid または名前 |
| `X_BOT_USER_ID` | 自アカウントの X ユーザーID（自分のリプを除外） |

## `campaigns` シート

| 列 | 型 | 説明 |
|---|---|---|
| campaign_id | string | 任意の一意ID |
| prize | string | 例: 副業スタートガイドPDF |
| hashtag | string | 例: #副業ノウハウプレゼント |
| keyword | string | リプ本文に含むべき語（例: 参加） |
| deadline | string | 表示用の締切文言 |
| status | enum | `queued` / `running` / `done` |
| tweet_id | string | 投稿後に自動で書き込まれる |
| posted_at | ISO | 投稿時刻 |

## `applicants` シート

| 列 | 型 | 説明 |
|---|---|---|
| campaign_id | string | |
| tweet_id | string | 一意キー（リプの tweet id） |
| author_id | string | |
| username | string | |
| name | string | |
| text | string | リプ本文 |
| created_at | ISO | |
| status | enum | `entered` / `winner` / `dm_sent` |
| drawn_at | ISO | 抽選時刻 |
| dm_sent_at | ISO | DM送信時刻 |

## `autoreplies` シート

| 列 | 型 | 説明 |
|---|---|---|
| campaign_id | string | |
| reply_id | string | 一意キー（自分が返信した元リプの id） |
| author_id | string | |
| username | string | |
| original_text | string | |
| generated_reply | string | AI生成本文 |
| posted_at | ISO | |

## `persona` シート（単一行）

| 列 | 例 |
|---|---|
| handle | @your_handle |
| worldview | 「会社に縛られず、通勤中にコツコツ育てる副業」を発信 |
| tone | フレンドリーで断定的、絵文字は控えめ、箇条書き多め |
| target | 副業を始めたい20-30代の会社員 |
| ng_words | 「絶対稼げる」「誰でも月100万」など誇大表現 |
| voice_samples | 過去に伸びたポストを2〜3件改行区切りで貼る |

## `posts` シート（仮説→ポスト生成ログ）

| 列 | 型 | 説明 |
|---|---|---|
| created_at | ISO | |
| category | string | 副業ノウハウ / マインド / ... |
| hypothesis | string | ユーザー入力の仮説 |
| variant_index | number | 1..N |
| hook | string | 冒頭フック |
| post_text | string | 投稿本文（140字以内） |
| reason | string | なぜ伸びるかの要約 |
| research_json | string | Claudeのリサーチ結果JSON |
| posted | bool | X投稿したか |
| tweet_id | string | |
| posted_at | ISO | |

## 運用フロー

1. `campaigns` に `status=queued` の行を追加 → 毎日19:00JSTで投稿
2. 10分おきに `applicants` へ応募者を upsert
3. 締切後、`02_Lottery_and_Winner_DM` を手動実行（`dry_run=true` で確認 → `false` で本番DM）
4. 並行して `03_AI_Engagement_AutoReply` が5分おきに新規リプへ自然な返信を生成
5. 思いついた仮説は `04_Hypothesis_to_Engaging_Post` のフォームに入力 → AIが裏付け&複数案生成 → variant 1 のみ自動投稿、全案は `posts` シートに保存
