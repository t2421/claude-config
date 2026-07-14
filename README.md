# claude-config — 自作の Claude Code ルール & スキル

Claude Code の個人設定のうち、**自分で書いたルールとスキル**をバージョン管理するリポジトリ。

## 位置づけ (2層構造)

| 層 | ソース | 役割 |
|---|---|---|
| ベース | [everything-claude-code](https://github.com/affaan-m/everything-claude-code) のクローン (`~/everything-claude-code`) | 上流の汎用ルール・スキル集。**直接編集しない** (pullを綺麗に保つ) |
| オーバーレイ | このリポジトリ | 自作分。`./install.sh` で `~/.claude/` に重ねる (同名は上書き) |

## セットアップ (新しいマシン)

```bash
# 1. ベース
git clone https://github.com/affaan-m/everything-claude-code.git ~/everything-claude-code
cd ~/everything-claude-code && ./install.sh web swift   # 使う言語を選ぶ

# 2. オーバーレイ (このリポジトリ)
./install.sh
```

## 運用ルール

- 新しいルール/スキルは **必ずこのリポジトリに書いてから** `./install.sh` で反映する
  (`~/.claude/` を直接編集すると、この履歴から漏れて消失リスクになる)
- 上流ECCのルールを直したくなったら: 上流にPRを送るか、同名ファイルをこちらに置いて上書きする
- プロジェクト固有の値 (デバイスUDID・スクリプト等) は各プロジェクトのリポジトリへ。
  ここに置くのは汎用の原則と手順だけ

## 内容

- `rules/common/deployment.md` — 修正後はユーザーの検証環境へ必ず配信する原則
- `rules/swift/deployment.md` — iOS: テスト後に実機配信、deployスクリプトの要件
- `skills/ios-device-deploy` — 実機配信 (プロファイル借用リサイン) の手順書
- `skills/codex-sol` — Codex CLI へのタスク委譲手順
