# 03_AI_Engagement_AutoReply 使い方マニュアル

「キャンペーン告知へのリプに、AIが自然な返信をつけてエンゲージメントを稼ぐ」フル自動ワークフローです。事故リスクが一番高い自動化なので、**段階的に有効化**してください。

---

## 1. ざっくりフロー

```
Every 5 min ──▶ campaigns(running) 取得
      ──▶ X search（conversation_id, 過去15分, bot除外）
      ──▶ autoreplies で既返信チェック
      ──▶ （新規のみ）Claude 返信生成
      ──▶ 140字にサニタイズ ──▶ X に in_reply_to で返信
      ──▶ autoreplies に append ──▶ Wait 30s
```

---

## 2. 事前準備

- 01 でキャンペーンが `running` になっていること
- `X_BOT_USER_ID` env に自分の数値IDが入っていること（自分の返信を除外するため）
- Anthropic API キーが Credentials に登録済

### 初回は必ず「Dry Post」モードで

`Post Reply` ノードを右クリック → **Deactivate**（無効化）し、`autoreplies` シートには案だけ溜めるモードから始めます。3〜4件生成された時点でシートを開いて文面をチェック:

- アカウントのトーンと合っているか
- 誘導文が自然か（プロフリンク訴求が押し売りになっていないか）
- 誤情報や差別的表現が混ざっていないか

問題なければ `Post Reply` を再度 Activate。

---

## 3. 有効化の手順

### Phase 1: ドライ運用（初日〜3日）
1. ワークフローを **Active** にする前に `Post Reply` を **Deactivate**
2. Active 化
3. 5分おきに Claude が返信案を生成 → `autoreplies` に溜まる
4. 最低20件見て品質 OK なら Phase 2 へ

### Phase 2: 半自動（数日）
1. `Post Reply` を有効化
2. ただし `Every 5 min` を `Every 30 min` に変更
3. Executions を毎日チェック、DMに変な返信が行っていないか確認

### Phase 3: 本稼働
1. `Every 5 min` に戻す
2. `Wait 30s` も状況に応じて 10 〜 60 秒で調整

---

## 4. Claude プロンプトの要点

`Claude Generate Reply` ノードの prompt はこう設計されています（概要）:

- **役割**: 副業ノウハウを発信するコミュニティマネージャー
- **制約**: 120字、絵文字≤2、プロフリンク訴求1回、ハッシュタグなし、「必ず当選」禁止
- **入力**: 相手の username / 表示名 / bio / リプ本文
- **出力**: 返信本文のみ（引用符や説明文なし → Sanitize 関数が二重に除去）

### プロンプトを編集するとき
- 「プロフのリンクに無料ガイド置いてます✨」の部分を自分の LP 誘導文に差し替える
- トーンを変えたい場合は「コミュニティマネージャー」→「先輩副業者」など立場を調整
- **NGワードを追加する場合**は `- 〜の単語は使わない` の1行を制約リストに足す

### モデル選択
- 品質重視: `claude-sonnet-4-6`（デフォルト）
- コスト重視: `claude-haiku-4-5-20251001`（約1/5）
- 返信量が多い場合は Haiku で十分、というケースが多い

---

## 5. 既返信チェックの仕組み

`Check Already Replied` が `autoreplies` シートを `reply_id` で引き、**ヒットすれば `$json.reply_id` は empty でなくなる**という挙動を使っています。`Is New?` は `reply_id` が **empty** を新規判定とする分岐。

> 注意: Google Sheets ノードの「ヒットなし時の挙動」はバージョンで変わります。ヒットなしで空オブジェクトでなく空配列になる版では、判定条件を変える必要があります。動作が怪しいときは先に `Check Already Replied` ノードの出力 JSON を開いて、ヒット/ミス時の形を確認してください。

---

## 6. 事故を防ぐガード

### 6.1 返信件数の上限を入れる
Function ノードを `Is New?` の直後に追加:
```javascript
const MAX_PER_RUN = 5;
return items.slice(0, MAX_PER_RUN);
```
→ 1 run あたり最大5件までに抑制。

### 6.2 怪しいリプを除外
`Flatten Replies` の末尾を書き換え:
```javascript
const banned = ['DM送った', 'クリックして', 'http://', 'https://bit.ly'];
for (const t of (res.data || [])) {
  if (banned.some(b => t.text.includes(b))) continue;
  // ...既存処理
}
```

### 6.3 API エラーで止まらない
`Post Reply` の Settings → **Continue On Fail** を有効化。失敗しても後続の `Log AutoReply` が通るので、後で手動リトライ可能。

---

## 7. X 自動化ポリシーへの配慮

X の [Automation Rules](https://help.x.com/en/rules-and-policies/x-automation) に準拠するため、以下は守ってください:

- 攻撃的/政治的リプには返信しない（プロンプトで排除しきれないので Function で単語フィルタも併用）
- 同じ文面の連投禁止（本ワークフローは毎回 Claude が変えるのでOK）
- 1日あたりの返信数が異様に多いとスパム判定される → 1日50〜100件を上限目安に
- bio/プロフィールに「AIが一部返信しています」と明記するのがベター

---

## 8. 監視チェックリスト

毎日5分で回す:
- [ ] `autoreplies` の昨日分を10件ランダムに読む（違和感がないか）
- [ ] Executions の赤失敗がないか
- [ ] X の自分のアカウントで、不自然な返信連投になっていないか肉眼確認
- [ ] 返信率（リプ数 / 返信数）が 80%以上で推移しているか（取りこぼしなし）

---

## 9. よくあるつまずき

| 症状 | 原因 | 対処 |
|---|---|---|
| Claude ノード 401 | API キー失効 | Credential 更新 |
| 同じリプに複数返信 | `Check Already Replied` のヒット判定が崩れた | ノードを Execute して出力 JSON 確認、IF条件を調整 |
| 返信が全部似た語尾 | Temperature が低い | `options.temperature` を 0.8 → 0.9 に |
| プロフ誘導が毎回違う | プロンプトで固定したいなら具体の一文をプロンプトにベタ書き |
| 文字数オーバー警告 | Sanitize が 140字で切っている | 既に自動で切られているので投稿は成功。気になるならプロンプトの文字数指示を 100字 に下げる |
