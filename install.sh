#!/bin/bash
# 自作ルール・スキルを ~/.claude/ に重ねる (個人オーバーレイ)。
#
# インストールの2層構造:
#   1. ベース:      ~/everything-claude-code の install.sh (上流ECCのルール/スキル)
#   2. オーバーレイ: このスクリプト (自作分。同名ファイルは上書き = こちらが勝つ)
#
# 何度実行しても安全 (冪等)。新しいルール/スキルを足したらこのリポジトリに
# コミットしてから再実行する。
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p ~/.claude/rules ~/.claude/skills

cp -R rules/ ~/.claude/rules/
cp -R skills/ ~/.claude/skills/
cp CLAUDE.global.md ~/.claude/CLAUDE.md   # 全プロジェクト共通の大元ルール

echo "installed:"
find rules skills -type f | sed 's|^|  ~/.claude/|'
echo "  ~/.claude/CLAUDE.md (from CLAUDE.global.md)"
