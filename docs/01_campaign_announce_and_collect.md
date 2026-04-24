# 01_Campaign_Announce_and_Collect 使い方マニュアル

「キャンペーン告知ポストを自動投稿 → リプライを定期監視 → 応募者を Sheets に集計する」ワークフローです。

---

## 1. ざっくりフロー

```
【上段】Daily 19:00 JST ──▶ campaigns から queued 取得 ──▶ 告知文ビルド ──▶ Xに投稿 ──▶ status=running 更新
【下段】Every 10 min ──▶ campaigns の running を取得 ──▶ X search（conversation_id）──▶ keyword filter ──▶ applicants に upsert
```

上段と下段は **同じワークフロー内で独立して動く2系統のトリガー** です。どちらも Active にして初めて本来の動きになります。

---

## 2. 事前準備

`docs/00_setup.md` を完了していることが前提。加えて:

- `campaigns` シートに告知したい行を `status=queued` で追加
- 自アカウントが X から通常投稿できる状態になっている（シャドウバンでない等）

### `campaigns` 行の例
| 列 | 値 | 説明 |
|---|---|---|
| campaign_id | cmp_20260501 | 任意の一意ID。`applicants` 集計の紐付けに使われる |
| prize | 副業スタートガイドPDF | 告知文の `{prize}` に入る |
| hashtag | #副業ノウハウプレゼント | 告知文末尾。応募者が真似して付ける前提 |
| keyword | 参加 | リプ本文にこの語が含まれていれば応募とみなす |
| deadline | 5/3 23:59まで | 表示用テキスト |
| status | queued | `queued` → `running` → `done` の状態機械 |
| tweet_id | （空） | 投稿後に自動で書き込まれる |
| posted_at | （空） | 同上 |

---

## 3. ワークフローをオンにする

1. n8n で `01_Campaign_Announce_and_Collect` を開く
2. 右上トグルで **Active** に
3. 2トリガーどちらも自動で回り始めます
   - **上段 `Daily 19:00 JST`**: 毎日 19:00 JST（UTC 10:00）に1回
   - **下段 `Every 10 min`**: 10分ごと

---

## 4. 一連の使い方（1キャンペーン分）

### Step 1: 仕込み
- 前日までに `campaigns` に `status=queued` 行を1つ追加

### Step 2: 自動告知（何もしない）
- 翌日 19:00 に自動投稿 → `status=running`、`tweet_id`、`posted_at` が埋まる
- 手動で動かしたい場合: 上段の `Daily 19:00 JST` ノードを右クリック → **Execute Node**

### Step 3: 応募者集計（何もしない）
- 10分ごとに `conversation_id:{tweet_id}` で検索 → keyword 一致リプを `applicants` に upsert
- `tweet_id` が一意キーなので、同じリプを何度拾っても行は増えません
- シートを開いて `status=entered` の行数が増えていけばOK

### Step 4: 締切後
- 締切時刻を過ぎたら手動で `campaigns.status` を `done` に変更
  - → 下段のリプ収集が止まる（`running` でなくなるため）
- その後、**02 の抽選ワークフロー** に進む

---

## 5. 告知文の中身

`Build Post Text` ノードで以下のテンプレで組み立てます。書式を変えたい場合はこの Function ノードを直接編集してください。

```
【{prize} プレゼント企画】

参加方法
1) このアカウントをフォロー
2) この投稿をリポスト
3) {hashtag} を付けてリプで「参加」と一言

抽選で当選者にDMします！
締切：{deadline}
```

- X の文字数上限(280 / 日本語は体感140)を超えないよう、prize と hashtag は短めに
- **フォロー必須**を明記すると後で DM が送れる率が上がる（02 で必要）

---

## 6. カスタマイズ例

### 6.1 時刻を変えたい
`Daily 19:00 JST` ノードの cron を変更:
- 毎日 21:00 JST → `0 12 * * *`（n8n は UTC で動くため -9 時間）
- 平日のみ → `0 10 * * 1-5`

### 6.2 リプ収集間隔を短くしたい
`Every 10 min` の `minutesInterval` を `5` などに。ただし X API の rate limit に注意（Basic は search 15分あたり60req）。

### 6.3 キーワードを複数にしたい
`Filter Valid Entries` Function ノードを以下に書き換え:
```javascript
const keywords = (campaign.keyword || '参加').split('|');
if (!keywords.some(k => t.text.includes(k))) continue;
```
→ `campaigns.keyword` を `参加|応募|欲しい` のように書く

### 6.4 リツイートも応募条件にしたい
公開 API ではリツイート有無を確実に取るのが難しいので、n8n 側では判定せず、投稿テンプレで「リポスト＋リプ両方必須」と明記して、当選者連絡時に目視確認するのが現実的。

---

## 7. よくあるつまずき

| 症状 | 原因 | 対処 |
|---|---|---|
| 告知が流れない | 上段だけ Active でも cron 時刻前は動かない | Execute Node で手動発火して確認 |
| `queued` が読まれない | シートに queued 行が複数あるとき、1行しか取られない | 必ず「次に打つ1件だけ queued」に保つ |
| 応募者が0 | keyword が厳しすぎる / conversation_id が別 | キーワードを緩めるか、tweet_id が正しく入っているか確認 |
| 自分の返信も収集されてしまう | 01 では bot 除外していない | 下段 `Fetch Replies` の `query` に ` -from:{{$env.X_BOT_USER_ID}}` を追加 |
| 行が二重に増える | Upsert の matchingColumns=tweet_id がヘッダ不在 | ヘッダに `tweet_id` 列があることを確認 |

---

## 8. 監視チェックリスト

毎朝10秒で見る用:
- [ ] `campaigns` に `running` 行があるか
- [ ] `applicants` の今日の `created_at` 件数が増えているか
- [ ] 前日の `posted_at` が入っているか（= 告知が飛んだ）
- [ ] n8n の Executions タブで赤い失敗が溜まっていないか
