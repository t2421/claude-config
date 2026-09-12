---
name: llm-wiki-lint
description: >
  Markdown で運用する個人 LLM wiki（raw 層 + 派生層 + INDEX/LOG）の定期健康診断の手順と
  機械チェックのスクリプト。リンク切れ・孤児ページ・INDEX/README との突合・frontmatter の
  出典欠落と陳腐化・「明日」「来週」などの相対日付を一括検出する。「wiki を整理して」
  「lint して」「陳腐化を洗って」「リンク切れを見て」等で使う。
---

# LLM wiki の lint（定期健康診断）

## いつ使うか

- 「wiki / 経歴 / 議事を整理して」と頼まれたとき（ingest ではなく **状態の整合**を求められている）
- 派生ページ（entities / concepts / analyses）が raw より古くなっていそうなとき
- 数日以上 ingest が続いた後。状態ハブ（overview・進捗表・応募先シート）は数日で必ず腐る

## 手順

1. **構造ドキュメントを読む**: AGENTS.md → wiki/SCHEMA.md → wiki/INDEX.md → wiki/overview.md。
   何が raw（書き換えない）で何が派生（作り直してよい）かを先に固定する。
2. **機械チェックを走らせる**: `python3 templates/wiki-lint.py --root .`（下記）。
   出力は「本当に直すもの」と「意図的に残すもの」に分ける。LOG の過去行のリンク切れなど、
   運用ルールで「履歴として保持」と決めたものは直さない。
3. **外部ソースとの差分**を見る（Notion / カレンダー等の取込口）。未取込があれば ingest は別タスクとして報告。
4. **状態ハブを今日の日付に揃える**: overview の「いま起きていること」、進捗表、応募先別シート、
   projects/README。**相対日付（明日・来週・今週）は絶対日付か「日時未記録」に置換**する。
5. **過去 LOG の「次の lint で直す」を回収する**。書きっぱなしの宿題が一番残りやすい。
6. **記録の欠け・日程衝突を lint ページに登録**する（推測で埋めない。本人確認要と書く）。
7. wishlist（INDEX の「書きたいが未着手」）に、raw が揃って書けるようになった項目があれば **その場で書く**。
8. lint ページの「最終実施」と件数、INDEX の一行要約、LOG エントリを更新。派生ページの `updated` は
   **内容を見直したものだけ**上げる（機械的に全部上げない）。

## ハマりどころ

- **同名の別ルートを混同しない**（例: 同じ社名でフリーランス案件と正社員応募が別々に走っている）。
  「お見送り」がどちらのルートかを raw で確かめてから状態を変える。
- **raw は書き換えない**。lint で見つけた事実の食い違いは lint ページに登録し、本人判断に回す。
  「据え置き」と決まった項目は再掲しない。
- 「明日」「来週」は書いた翌日から嘘になる。派生ページと面接準備資料には書かせない。
- `updated` < 出典の最終コミット日 は **候補**にすぎない（resume を1行直しただけで全 concept が引っかかる）。
  中身を見て判断する。

## スクリプト

`templates/wiki-lint.py` — 引数なしで動く。ディレクトリ名は既定値（`wiki/`, `meetings/`, `career/`, `projects/`）で、
`--derived` `--raw` `--index` で差し替えられる。

```bash
python3 ~/.claude/skills/llm-wiki-lint/templates/wiki-lint.py --root . \
  --ignore-link 'YYYY-MM-DD-slug.md' --ignore-link 'hajimari-qa.md'
```

出力セクション: BROKEN LINKS / ORPHANS / NOT IN INDEX / MEETINGS NOT IN README / FRONTMATTER（NO SOURCES・STALE候補）/
RELATIVE DATES（明日・来週・今週・翌日）。
