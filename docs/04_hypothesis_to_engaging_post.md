# 04_Hypothesis_to_Engaging_Post 使い方マニュアル

「これ伸びそう」という仮説をフォームに入れると、AIが裏付けリサーチ → アカウントの世界観に合わせて複数案ポスト生成 → 1案を自動投稿 + 全案を Sheets に保存するワークフローです。

---

## 1. ざっくりフロー

```
Form（hypothesis / category / variants / dry_run）
    ──▶ persona シート読込
    ──▶ Claude リサーチ（verdict / 根拠 / 反証 / フック案 を JSON で返す）
    ──▶ Claude ポスト生成（variants 案、140字以内）
    ──▶ variant_index=1 かつ dry_run=false → X 投稿
    ──▶ 全 variants を posts シートに保存
    ──▶ Webhook Respond
```

---

## 2. 事前準備

- `persona` シートに1行埋まっていること（00_setup.md §3.4）
- `posts` シートが用意されていること
- Anthropic API が動くこと

### persona の書き方例
| 列 | 書き方のコツ |
|---|---|
| worldview | 2〜3行で「誰のどんな課題に、どう寄り添うアカウントか」 |
| tone | 「ですます vs だ調」「絵文字頻度」「箇条書き多め」など文体指示 |
| target | ペルソナ1人を具体に（例: 27歳SEで副業に興味あるが時間がない） |
| ng_words | 過去クレームが来た表現、薬機法/景表法に触れる単語 |
| voice_samples | 過去に自分でバズった投稿を2〜3件コピペ。**これが一番効く** |

---

## 3. 使い方（1回の投稿生成）

### Step 1: ワークフロー起動
1. n8n で `04_Hypothesis_to_Engaging_Post` を **Active** に（Form トリガーは Active でないと URL を受けない）
2. フォームの Production URL を控える（ノード画面右上）

### Step 2: フォーム入力
ブラウザでフォーム URL を開き:
- **hypothesis**: 「副業初心者は月1万円より通勤30分でできるの方が刺さる」
- **category**: 副業ノウハウ
- **variants**: 3（1〜3 推奨）
- **dry_run**: **true**（初回は必ず）

### Step 3: `posts` シートで確認
- 3行 append されている（variant 1〜3）
- `hook` / `post_text` / `reason` / `research_json` が入っている
- どれが一番刺さるか目視で判定

### Step 4: 本投稿
- 良い案があれば dry_run=false で同じ hypothesis を再送（Variant 1 だけ自動投稿）
- または `posts` シートの `post_text` を手動コピー → 手動で X に投稿（最終品質確認を挟める）

> **推奨運用**: 基本は `dry_run=true` で案出し、人間が選んで手動投稿。週1回だけ `dry_run=false` で完全自動、みたいなハイブリッド。

---

## 4. 出力されるもの（posts シート）

| 列 | 例 |
|---|---|
| created_at | 2026-04-24T10:15:00Z |
| category | 副業ノウハウ |
| hypothesis | 月1万円より通勤30分で〜 |
| variant_index | 1 |
| hook | 「月1万円稼ぐ」が続かない理由、たぶん逆 |
| post_text | 「月1万円稼ぎたい」で始めた副業、半年で9割が消える。 / 続く人は…（以下140字） |
| reason | 数字訴求より行動の具体に寄せた方が共感されやすい |
| research_json | `{"verdict":"partially_true",...}` |
| posted | true（dry_run=false で variant 1 のみ） |
| tweet_id | 1789... |
| posted_at | 2026-04-24T10:15:12Z |

`research_json` は後から「この仮説は裏が取れていたか」をレビューするのに便利。

---

## 5. Claude の2パス構成について

このワークフローは **リサーチ → 作文** の2段で Claude を呼んでいます。

### 5.1 Research パス（temperature=0.4）
仮説に対して、verdict（likely_true / partially_true / likely_false）と根拠・反証・切り口を構造化 JSON で返す。ここで正直に partially_true が出ることで、過剰な断言投稿を抑制できる。

### 5.2 Craft パス（temperature=0.9）
Research 結果とペルソナを全部入れて、140字 × variants 案のポストを JSON で返す。高温にしてあるので毎回違う切り口が出る。

> 同じ仮説を2回送ると、毎回違う案が出ます。気に入らなかったら何度でも回せば OK。

---

## 6. カスタマイズ

### 6.1 案の評価軸を増やす
`Claude Craft Posts` の出力 JSON に項目を追加:
```json
{"hook":"...", "text":"...", "reason":"...", "engagement_score": 1-10, "risk":"low|mid|high"}
```
プロンプト側に「engagement_score を控えめに自己採点、risk は景表法/薬機法/誇大表現の懸念度」と指示。

### 6.2 CTA パターンを切り替える
現状は「保存したくなる要約 or 問いかけ」一択。複数パターンを A/B したい場合:
- フォームに `cta_type` dropdown を追加（保存誘導 / 共感コメ誘導 / リプ誘導）
- プロンプトに `{{$json["cta_type"]}} に合わせた CTA にする` を追記

### 6.3 投稿する variant を選べるように
現在は variant_index=1 固定。`Post Variant 1?` の IF を以下に変えると、フォームで投稿する案番号を指定可能:
```
{{$json["variant_index"]}} == {{$json["post_variant"]}}
```
フォームに `post_variant` 番号フィールドを追加。

### 6.4 画像付き投稿にする
`Post to X` ノードのあとに DALL·E / Flux / Stable Diffusion 系のノードを挟み、画像URLを `mediaIds` で添付。Twitter ノードの `additionalFields` に `attachments.media_keys` を指定する構成になる。

---

## 7. プロンプト改善のコツ

### 伸び率が低いとき
- `voice_samples` を最新のバズ投稿に入れ替える（3ヶ月ごとに更新推奨）
- Craft プロンプトに「冒頭10字で止めさせる」の制約を追加
- Research の `hook_ideas` が薄い → `verdict` に関わらず「意外な切り口」を必ず1つ出すよう指示

### 怪しい数字が出たとき
- Research プロンプトの「一般に広く知られた知見に留めてください」を強調
- Craft プロンプトに「数字は Research の supporting_points に登場したものだけ使う」を追加

---

## 8. コスト目安（2026年Q2時点の目安）

- Sonnet 4.6: 仮説1件あたり $0.02〜0.05（input 2k token + output 1k token × 2パス）
- Haiku 4.5: 同 $0.005〜0.01
- 1日5件生成 × 30日 = Sonnet で月$3〜7程度

運用当初はSonnetで品質を見て、安定したらHaikuに寄せるのが現実的。

---

## 9. よくあるつまずき

| 症状 | 原因 | 対処 |
|---|---|---|
| Form が開かない | Inactive | Active にする、Production URL を使う |
| `Parse Research` で空 | Claude が JSON ブロックで返さなかった | 既に正規表現で抜いているはずだが、失敗時は raw を見る → プロンプトに「JSON 以外は絶対に書くな」を強く追加 |
| posts シートが更新されない | Sheet 名/列名不一致 | ヘッダ完全一致を確認 |
| 毎回同じ文面 | temperature が低い / voice_samples が固い | voice_samples を増やす、temperature=1.0 にしてみる |
| 投稿されない | dry_run=true のまま | フォーム入力を確認 |
| 文字数が微妙に超える | 絵文字が2文字カウント | Sanitize 不要なら OK、気になるなら slice(0, 130) に下げる |

---

## 10. レビュー運用の推奨

週に1回 `posts` シートを開いて:
- `posted=true` の行の実際のインプレッション・いいね数を手動 or API で入れる列（`impressions`, `likes`, `retweets`, `replies`）を追加
- `reason` に書いた仮説と結果のギャップを見る
- 当たった hook パターンを persona の `voice_samples` に追加して学習ループ

このループを回すと、ペルソナ・仮説・投稿の3点がじわじわ研ぎ澄まされていきます。
