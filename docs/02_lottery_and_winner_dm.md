# 02_Lottery_and_Winner_DM 使い方マニュアル

「締切後の応募者リストから抽選 → 当選者にDMを半自動送信」するワークフロー。事故を防ぐため `dry_run` を必ず挟む二段構成です。

---

## 1. ざっくりフロー

```
Manual Trigger ──▶ フォーム（campaign_id / winners / dry_run）
        ──▶ applicants（entered）取得 ──▶ author_id で重複排除
        ──▶ Fisher-Yates 抽選 ──▶ status=winner 更新
        ──▶ dry_run?
              ├─ true  → 終了（当選者確認だけ）
              └─ false → X DM 送信 ──▶ status=dm_sent 更新
```

---

## 2. 事前準備

- 01 が動いていて `applicants` に `status=entered` が十分に集まっている
- 当選者DMを送る先の **Xアカウントが自分をフォローしている** こと（DM 必須条件）
- 当選者へ渡す URL（特典受け取り先）を決めておく

### 特典URL差し替え
`Send Winner DM` ノードの `jsonBody` 内を編集:
```json
"text": "🎉 ご当選おめでとうございます！...\nhttps://your-landing.example.com/gift?u={{$json[\"author_id\"]}}"
```
`?u={{author_id}}` を付けておくと、ランディング側でクリック解析・重複受取り防止に使えます。

---

## 3. 抽選の流れ（本番手順）

### Step 1: 締切を迎える
`campaigns` の対象行の `status` を手動で `done` に（01 の収集を止める）。

### Step 2: dry_run で当選者だけ確定
1. n8n で `02_Lottery_and_Winner_DM` を開く
2. **Execute Workflow**（左下）を押す
3. フォームが開くので入力:
   - `campaign_id`: `cmp_20260501` 等
   - `winners`: 当選者数（例: 5）
   - `dry_run`: **true**
4. 実行後、`applicants` の該当5行が `status=winner` / `drawn_at` 入り状態になる
5. シートでその5行を目視チェック
   - 荒らしアカウント / 明らかなbot / フォローしていない人 はここで除外（手動で `status` を `excluded` などに変更）

### Step 3: 本番送信
1. もう一度 Execute Workflow
2. フォームに同じ `campaign_id`、`winners`、`dry_run`=**false**
3. **ただし**、ステップ2で絞った行しか残っていないよう `winners` の数を合わせて指定

> コツ: dry_run 後に対象を絞った場合は、残った winner 行数 = 新しい `winners` 値 になるように調整してください。抽選は `status=entered` から引くので、winner 扱いになった行は再抽選対象になりません。

### Step 4: ログ確認
- `applicants.status` が `dm_sent`、`dm_sent_at` が埋まっていれば成功
- X 側の送信済みDMと突合

---

## 4. なぜ dry_run が必要か

- X の DM API は返信がない場合でも送信回数を消費する
- 荒らし/業者アカウントに誤送信すると特典URLが流出しかねない
- **法的には「抽選の公正性」記録も必要**（景表法）→ dry_run 時点の winner リストを保存しておくと証跡になる

---

## 5. カスタマイズ

### 5.1 DM文面を変える
`Send Winner DM` の `jsonBody` をそのまま日本語で書き換え。改行は `\n`、絵文字はそのまま使えます。

### 5.2 手動送信に切り替えたい
`Actually Send?` の IF を常に false 側に通せばDM送信が走らず、`status=winner` だけがつきます。送信は DM 文面を自分でコピペして手送り。最も事故が少ない運用。

### 5.3 当選者を X で公開告知する
分岐を増やすか、`Send Winner DM` の後に `Post Campaign Tweet`（01 と同じノード）を追加して、以下のような祝賀ポストを流す:
```
🎉当選者発表🎉
@{{username}} さん おめでとうございます！
DMをご確認ください✨
```

### 5.4 1アカウント複数応募対策を厳しく
現在は `author_id` で dedup 済。さらに「当選履歴のあるユーザーは除外」したい場合、`Draw Winners` Function の冒頭に過去当選シートを読む処理を足す。

---

## 6. よくあるエラー

| 症状 | 原因 | 対処 |
|---|---|---|
| フォームが開かない | Execute Workflow ではなく Active にしている | 手動実行は Inactive のまま Execute Workflow ボタン |
| `Load Applicants` が0件 | `status=entered` 行が無い / `campaign_id` ミス | シート直接確認 |
| DM 403 code 349 | 相手が未フォロー / DM受信拒否 | その行を excluded にして再抽選 |
| DM 429 | レート制限 | `Send Winner DM` の後に `Wait 10s` を挟む |
| `winner` が想定と違う数 | `winners` に文字列が入っている | 数値で入力 |
| 複数キャンペーンを混同 | `campaign_id` フィルタで区別 | 必ずフォームに正しい id を入れる |

---

## 7. 月次運用の推奨

- キャンペーン1回ごとに抽選Runのスクショを残しておく（n8n Executions 画面）
- 当選者DMは 24h 以内に送る（X の慣習）
- 未使用の winner 行（DM送信前に reject 判定したもの）は週次で整理、`status=excluded` に揃える
