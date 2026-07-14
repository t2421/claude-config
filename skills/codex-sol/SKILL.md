---
name: codex-sol
description: >-
  Claude Code から Codex CLI（既定モデル gpt-5.6-sol / reasoning xhigh）にタスクを委譲する手順。
  「codex に〜させて」「codex sol でレビュー/修正/実装させて」「別モデルにセカンドオピニオンを」
  等の依頼、または大きなレビュー・リファクタ・独立したコード生成を Codex に丸ごと任せたい時に使う。
  レビューのみ・レビュー+修正・独立タスク実装の3パターンと、安全な回し方をまとめている。
---

# Codex sol への委譲

ローカルの `codex` CLI（OpenAI Codex CLI）を使い、Claude から Codex（既定 `gpt-5.6-sol`）に
コードレビュー・修正・実装を非対話で任せる。Codex は別モデルなのでセカンドオピニオンとして有効。

## 前提の確認（最初の1回）

```bash
codex --version                 # 0.144.x を想定
codex login status              # "Logged in using ChatGPT" ならOK
grep -E '^model' ~/.codex/config.toml   # 既定モデル。通常 gpt-5.6-sol
```

- 既定モデル/推論強度は `~/.codex/config.toml`（`model = "gpt-5.6-sol"`, `model_reasoning_effort = "xhigh"`）。
  明示するなら `-m gpt-5.6-sol` や `-c model_reasoning_effort=high` を付ける。
- 未ログインなら、ユーザーに `! codex login` を実行してもらう（対話ログインは Claude 側からは不可）。

## 3つの使い分け

### 1) レビューのみ（差分に対する指摘。ファイルは変更しない）

```bash
codex review --uncommitted            # 未コミットの変更をレビュー
codex review --base main              # main との差分をレビュー
codex review "認証まわりを重点的に"    # レビュー観点をプロンプトで指定
```

差分ベースなので、レビューしたい変更は先にワークツリーに出しておく。

### 2) レビュー + 修正（Codex にファイルを直させる）— 最頻

```bash
# 開始前に必ずコミット（Codex の変更を diff で確認・巻き戻せるように）
git -C <repo> add -A && git -C <repo> commit -m "wip: before codex" 2>/dev/null; \
git -C <repo> rev-parse HEAD          # base commit を控える

codex exec -s workspace-write -C <repo> \
  -o /tmp/codex-summary.txt \
  "<レビュー+修正の指示>"
```

- `-s workspace-write` でワークツリー編集を許可（exec は `approval: never` で非対話進行）。
- `-o <file>` に Codex の最終まとめ（日本語で指示すれば日本語）が入る。
- 長丁場になるので **バックグラウンド実行**（Bash tool の run_in_background）+ 完了通知待ちが基本。
- サンドボックスの都合で Codex 自身がビルド/テストを回せないことがある → **完了後に Claude 側で必ず検証**。

### 3) 独立タスクの実装（新規機能・スクリプト生成など）

2) と同じく `codex exec -s workspace-write`。プロンプトに完成条件（テストが通る等）を明記する。

## プロンプトに必ず入れる安全条項

Codex は自律的にファイルを書き換えるので、指示文へ以下を明記する:

- gitignore 済みの機密（例: `Local.xcconfig`, `.env`）は変更・出力しない
- `git commit` / `push` はしない（ワークツリー編集のみ。コミットは人間/Claude が確認後に行う）
- 本番へのデプロイ（`supabase db push` 等）や外部への送信はしない
- 既存の意図的な設計判断を「バグ」と誤認して巻き戻さない（判断の根拠ドキュメントを読ませる）
- 最後に「見つけた問題」「行った修正」を重要度順に簡潔にまとめる

## 委譲後に Claude 側でやること（重要）

Codex は別プロセスで自己検証が不完全なことがあるため、受け取ったら必ず:

1. **差分レビュー**: `git -C <repo> diff <base-commit>` で Codex の変更を全部見る
2. **テスト実行**: そのプロジェクトのテスト一式を Claude 側で回してデグレ確認
3. 疑わしい変更・過剰な巻き戻しは選別して revert（`git checkout <base> -- <path>`）
4. 問題なければ通常フローでコミット

「Codex にやらせた＝そのまま採用」ではなく、**Codex=下請け、最終責任は Claude/人間**という前提で扱う。

## よく使うフラグ

| フラグ | 用途 |
|---|---|
| `-s read-only \| workspace-write \| danger-full-access` | サンドボックス。編集させるなら workspace-write |
| `-C <dir>` | 作業ディレクトリ |
| `-m <model>` | モデル上書き（既定は config の gpt-5.6-sol） |
| `-c key=value` | config 上書き（例 `-c model_reasoning_effort=high`） |
| `-o <file>` | 最終メッセージをファイル出力 |
| `--json` | イベントを JSONL で出力（進捗パース用） |
| `--add-dir <dir>` | workspace 外の追加書き込み許可ディレクトリ |

`--dangerously-bypass-approvals-and-sandbox` はサンドボックス無効化で危険。原則使わない。
