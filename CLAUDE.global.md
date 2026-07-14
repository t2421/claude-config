<!-- このファイルの正典は t2421/claude-config リポジトリ (CLAUDE.global.md)。
     install.sh が ~/.claude/CLAUDE.md へ配布する。直接編集せずリポジトリ側を編集すること。 -->

# 全プロジェクト共通の大元ルール

## スキル収穫 (最重要の習慣)

再利用できそうな手順・パターン・ハマりどころが生まれたら、**積極的に
t2421/claude-config へ収穫してコミット・pushする**。詳細な基準とワークフローは
`rules/common/skill-harvesting.md` を参照。迷ったら収穫する側に倒す
(ただし public リポジトリなので機密・プロジェクト固有値は除く)。

## 自作設定の管理

- 自作ルール/スキルの正典: `~/projects/t2421/claude-config` → `./install.sh` で `~/.claude/` に反映
- 上流ECC (`~/everything-claude-code`) は直接編集しない
