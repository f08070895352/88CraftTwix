# Campaign Playbook — 17施策 × 9ツールの組合せ表

17 の施策を 1 ファイル 1 ワークフローで作ると似たコードだらけになるので、
**再利用可能な 9 本のツール** に束ね、**施策ごとの合成レシピ**で運用します。

## ツール一覧

| ID | ファイル | 役割 |
|---|---|---|
| T1 | `workflows/a-entry-collector.json` | RT / 引用RT / リプライ参加者を `campaign_entries` に蓄積 (重複排除付) |
| T2 | `workflows/a-lottery-drawer.json` | 手動トリガで `campaign_entries` から抽選、当選者にDM |
| T3 | `workflows/b-thread-poster.json` | POSTで渡した N 件の文字列を in_reply_to チェーンでスレッド投稿 |
| T4 | `workflows/b-lead-magnet-deliverer.json` | 指定キーワードを含むリプライ者へ自動でPDFリンクDM |
| T5 | `workflows/c-limited-offer.json` | Stripe クーポン(時限)作成 + 告知ツイート一括 |
| T6 | `workflows/c-line-funnel.json` | LINE Messaging API の Webhookで友だち追加を CV 計上 |
| T7 | `workflows/d-poll-creator.json` | X ネイティブPoll投稿 + 1時間毎の結果スナップショット |
| T8 | `workflows/d-trend-monitor.json` | トレンド取得 → AIで自社との絡め判定 → Slackに下書き |
| T9 | `workflows/reply-to-dm-to-sales.json`（既存）| メインの「リプ→DM→販売」パイプライン |

## 施策 → ツール マッピング

### A. フォロワー獲得系 — KPI: フォロワー増加率 / インプレッション

| 施策 | 使うツール | 準備 |
|---|---|---|
| A-1 フォロー＆RTキャンペーン | T1 + T2 | `campaigns` に `type='follow_rt'`, `target_tweet_id` を登録。期間終了時に T2 を POST で叩く |
| A-2 抽選プレゼント | T1 + T2 | 同上。T2 に `prize_dm` で当選通知文を渡す |
| A-3 固定ポスト誘導 | 既存の自動リプ(T9) + T5 の告知部分 | 固定投稿の URL を `CHECKOUT_BASE_URL` に、T9 のAI返信で誘導 |
| A-4 引用RT参加型 | T1 (quote分岐が動く) + T2 | `target_tweet_id` を登録するだけ |
| A-5 コメント参加型 | T9 (既存) + T1 の reply分岐 | mentions 経由で拾うため T9 だけでもOK。横断集計するなら T1 に投入 |

### B. 教育・信頼構築系 — KPI: 保存率 / プロフクリック率

| 施策 | 使うツール | 準備 |
|---|---|---|
| B-1 スレッド型ストーリー | T3 | `POST /post-thread { campaign_id, tweets: [...] }` で投下 |
| B-2 無料特典配布 | T3（告知スレ）+ T4（配布） | B-1でスレ投稿 → 末尾ツイートに「欲しい人は"欲しい"とリプ」→ T4 が自動配送 |
| B-3 ノウハウ連投 | T3 のみ | 1スレ= 5-10投稿のノウハウ |
| B-4 ビフォーアフター | T3 のみ | 2投稿のスレ（before / after）|

※ 保存率・プロフクリックは X Analytics 経由で取得が必要。
`campaign_events` に `event='save'` / `'profile_click'` を手動または X Ads API / Twitter Analytics export から取り込む想定。

### C. 販売導線系 — KPI: CV率 / DM返信率

| 施策 | 使うツール | 準備 |
|---|---|---|
| C-1 リプ誘導 | T9 | 固定投稿/告知投稿に対する全リプを T9 が AI 判定 → DM |
| C-2 DM自動送信キャンペーン | T9 + 既存 `new-follower-welcome-dm.json` | フォロワー追加時・リプライ時の両方で発火 |
| C-3 限定オファー | T5 + T9 | `POST /create-limited-offer { hours: 48 }` でクーポン＋告知 → T9 で誘導 |
| C-4 LINE誘導 | T6 + T9 | T9 の DM 本文を LINE追加 URL に差し替え、友だち追加を T6 で CV 計上 |

### D. エンゲージメント強化 — KPI: いいね率 / コメント率

| 施策 | 使うツール | 準備 |
|---|---|---|
| D-1 アンケート投稿 | T7 | `POST /create-poll` で native poll |
| D-2 意見募集投稿 | T3 (1投稿) + T1 (reply分岐) | 呼びかけ投稿 → 返信者を entries に |
| D-3 炎上ギリの問題提起 | T8 のドラフトを**手動で**投稿 | AIが high-risk と判定したものは自動では流さない安全弁つき |
| D-4 トレンド便乗 | T8 | 下書きを Slack `#content-ideas` で承認→手動投稿 |

## 施策登録の基本ワークフロー

```sql
-- 例: A-1 フォロー＆RTキャンペーンを準備
insert into campaigns (id, category, type, title, target_tweet_id, starts_at, ends_at, config)
values (
  'a_rt_20260501',
  'A', 'follow_rt',
  'GW限定プレゼント',
  '1780000000000000000',
  now(), now() + interval '7 days',
  '{"prize": "商品A", "winners": 3}'::jsonb
);
```

これで 10分毎 Cron の T1 が自動で参加者を拾い、期間終了後に:

```bash
curl -X POST $N8N_URL/webhook/campaign-draw \
  -H 'content-type: application/json' \
  -d '{"campaign_id":"a_rt_20260501","winners":3,"prize_dm":"ご当選🎉 送り先を返信ください"}'
```

で抽選 → DM まで回ります。

## KPI レポート

`workflows/campaign-kpi-report.json` が毎朝9時に全アクティブキャンペーンの
カテゴリ別KPIを `#sales-daily` に投稿:

```
*📊 24hキャンペーンKPI*

*— カテゴリ A —*
• `follow_rt` *GW限定プレゼント*: 新規参加者=*248*  _imp=0 prof=0_

*— カテゴリ C —*
• `limited_offer` *春割48h*: CV=*12*  _dm=48 rev=¥117,600_
```

impression/profile_click/save の自動取得は Basic tier の X API だけでは不可。
これらは**手動で CSV から `campaign_events` に流すか、Twitter Analytics Export を別ワークフローで ETL** する運用になります。
