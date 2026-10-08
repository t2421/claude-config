---
name: split-subset-pr-from-dirty-tree
description: >-
  作業ツリーに別作業の未コミット変更が散らばっている状態で、「この部分だけ
  切り出して PR にして」と言われたときの手順。git stash で他人の作業に触れず、
  main から別 worktree を作って対象ディレクトリだけ rsync し、そこでテスト・lint・
  typecheck を通してからコミット・push・PR を作る。切り出した変更が「残した変更」に
  暗黙に依存していないことを、main の実装に対して実際に検証できるのが肝。
  「テストだけ PR にして」「ドキュメント分だけ先に出して」「このファイル群だけ別 PR」
  等で使う。
origin: user
---

# 汚れた作業ツリーから一部だけを切り出して PR にする

## 状況

- 作業ツリーに **自分の今回の変更** と **以前のセッション／他の作業の未コミット変更**
  が混ざっている (例: `src/` のリファクタ途中 + 今回の `tests/` 書き換え)。
- ユーザーは「今回の分だけ PR にして」と言う。`git add -p` で分けると、切り出した
  側が残した側の変更 (新しい export、改名した関数など) に依存していても気づけない。
- `git stash` は他の作業を一時的に消すので、復元ミスや hooks の再実行で事故りやすい。

## 手順

```bash
# 1. main から別 worktree + 新ブランチ (作業ツリーは一切触らない)
WT=<scratchpad>/split-pr
git fetch origin main
git worktree add "$WT" -b <branch> origin/main

# 2. 依存はストアから offline で (数秒で終わる)
(cd "$WT" && pnpm install --offline --frozen-lockfile)

# 3. 切り出したいディレクトリだけ同期 (--delete で削除も反映)
rsync -a --delete --exclude node_modules tests/ "$WT/tests/"
cp docs/GUIDELINES.md "$WT/docs/GUIDELINES.md"   # 単一ファイルは cp

# 4. main の実装に対して検証 (ここで落ちたら「残した変更」への暗黙依存)
(cd "$WT" && pnpm vitest run && pnpm eslint . --max-warnings 0 \
  && pnpm prettier --check . && pnpm vue-tsc --noEmit && pnpm exec playwright test)

# 5. コミット・push・PR は worktree 側で
(cd "$WT" && git add -A tests docs/GUIDELINES.md && git commit -F - <<'MSG'
...
MSG
git push -u origin <branch> && gh pr create --base main --head <branch> --body-file -)

# 6. 片付け。ブランチは残り、元の作業ツリーの未コミット変更も無傷
git worktree remove "$WT"
```

## ハマりどころ

- **`git status` に見覚えのない M がある**: 以前のセッションの残り (例:
  `.github/scripts/*.mjs`)。`git diff --stat` で中身を見て、自分の変更でなければ
  PR に含めない。rsync の対象を「自分が触ったディレクトリ」に限定すれば自然に除外される。
- **main に無い export を使っていた**: 手順 4 の typecheck/vitest で `has no exported
  member` 等が出る。切り出す側を main の API に合わせて書き直すか、依存する実装の
  変更も同じ PR に含めるかをユーザーに確認する。
- **Playwright の webServer が `strictPort`**: 元ツリーと worktree で同時に E2E を
  走らせない。片方ずつ。
- **worktree の削除忘れ**: `git worktree list` に残ると、同名ブランチを元ツリーで
  checkout できない。PR 作成後に `git worktree remove` する。
- **元の作業ツリー側のテスト変更はそのまま残る**: ユーザーが後で `src/` 側を
  コミットするとき、`tests/` の差分は PR ブランチと同じ内容なので rebase/merge で
  衝突しない (同一内容)。念のため PR マージ後に `git checkout main -- tests/` ではなく
  `git pull` で揃える。

## 判断の基準

- 切り出し対象が **ディレクトリ単位で分かれている** ならこの手順。
- 同じファイル内で行単位に混ざっているなら `git add -p` だが、その場合も手順 1〜4
  の worktree 検証を「`git diff > patch` → worktree で `git apply`」に置き換えて行う。
