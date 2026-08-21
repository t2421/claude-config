---
name: cloudflare-pages-ci-bootstrap
description: >-
  Cloudflare アカウントの新規取得から、Pages デプロイ用 API トークンの発行、
  GitHub Actions の Secrets 登録までを、人間の作業を最小に圧縮して立ち上げる手順。
  代行できる線とできない線 (Turnstile・規約同意・アカウント作成) の切り分け、
  メールエイリアスが使えない件、新形式トークン (cfut_ プレフィックス) の扱い、
  トークンを一度も画面に出さずに gh secret へ流す方法を含む。
  「Cloudflare のアカウント作って」「Pages のプレビュー環境作って」
  「CLOUDFLARE_API_TOKEN を用意して」等で使う。
origin: user
---

# Cloudflare Pages を CI から使えるようにする (人間作業最小化)

到達点: GitHub Actions が `wrangler pages deploy` を実行できる状態。
すなわち `CLOUDFLARE_API_TOKEN` と `CLOUDFLARE_ACCOUNT_ID` がリポジトリの Secrets に
入っており、そのトークンで対象アカウントの Pages API が 200 を返すこと。

## 全体の担当分け

| 作業 | 担当 | 理由 |
|---|---|---|
| Google アカウント新規作成 | 🧑 人間 | **アカウント作成は代行禁止**。画面を開くところまでしかできない |
| Cloudflare サインアップ画面を開く・メール欄を埋める | 🤖 Claude | 単なるフォーム入力 |
| パスワード入力 | 🧑 人間 | パスワードマネージャで生成・保管させる。代行禁止 |
| Turnstile「私はロボットではありません」 | 🧑 人間 | **ボット検出の突破は代行禁止**。一線 |
| Sign up クリック | 🧑 人間 | 利用規約への同意そのもの |
| Account ID の取得 | 🤖 Claude | ログイン後の dash URL から読める |
| API トークン発行 (Custom token) | 🤖 Claude | ダッシュボードの UI 操作で完結 |
| トークンを GitHub Secrets へ登録 | 🤖 Claude | クリップボード経由で値を画面に出さずに流せる |
| 権限の検証 | 🤖 Claude | `curl` で完結 |

要するに **サインアップ画面の「パスワード + Turnstile + Sign up」だけが人間**で、
前後は全部代行できる。ここを最初に宣言しておくと往復が減る。

## 1. メールアドレスを決める (最初のハマりどころ)

**Cloudflare は `user+tag@example.com` 形式のエイリアスを受け付けない** (2026-08 実測)。
Gmail のエイリアスで環境ごとにアカウントを分ける運用をしていると、ここで詰まる。

対処は独立したメールアドレスを取ること。ドット区切り (`user.tag@gmail.com`) は
Gmail 的には同一アカウント扱いだが、**Cloudflare からは別アドレスに見える**ので通る。
ただしその Gmail アカウント自体を新規に作る場合は、作成そのものが代行できない。

副作用として、**新しい Gmail の受信箱は Claude の Gmail MCP からは読めない**
(MCP は既存の 1 アカウントにしか繋がっていない)。確認メールを踏む必要が出たら、
ブラウザでそのアカウントにログインしたままにしてもらい、タブ経由で読む。

> 補足: `+alias` 宛のメールは、MCP が繋がっている親アカウントの受信箱に届くので
> **読める**。つまり「エイリアスが使えるサービス」なら確認メールまで完全代行できる。
> Cloudflare はそれができない側だった、というのがこの節の要点。

代替案として Cloudflare のサインアップ画面には
「Continue with Google / Apple / GitHub」がある。新しいメールを作らずに済むが、
Cloudflare アカウントが その identity に紐づく。分離したいなら選ばない。
**着手前にユーザーへ提示して選ばせる。**

## 2. サインアップ (人間に渡す)

```
https://dash.cloudflare.com/sign-up
```

Email 欄だけ埋めて、次の 3 点を明示して人間に渡す。曖昧に「サインアップして」と
言わず、**何を代行しないかを理由付きで書く**と一度で済む。

1. Password 欄に入力 (パスワードマネージャで生成・保存)
2. 「私はロボットではありません」にチェック
3. Sign up をクリック (規約同意なので本人が押す)

Turnstile はページ表示直後は「検証中…」と出て自動で通るように見えるが、
**フォームに入力すると対話チェックボックスに変わる**。自動で通る前提で待たない。

## 3. Account ID を取る

サインアップ完了後、ダッシュボードの URL がそのまま答え。

```
https://dash.cloudflare.com/<ACCOUNT_ID>/home
```

`ACCOUNT_ID` は 32 桁の hex。Secrets に入れるが秘密情報ではない (URL に出る)。

## 4. API トークンを発行する (最小権限)

`https://dash.cloudflare.com/profile/api-tokens` → **Create Token** →
**Create Custom Token / Get started**。テンプレートには Pages 用が無いので Custom を使う。

| 項目 | 値 |
|---|---|
| Token name | `<repo名> pages deploy` のように用途が分かる名前 |
| Permissions | `Account` / `Cloudflare Pages` / **`Edit`** |
| Account Resources | `Include` / **該当アカウント** (`All accounts` のままにしない) |
| Client IP Filtering | 空 (GitHub Actions の IP は固定できない) |
| TTL | 空 |

Permissions のプルダウンは react-select 系で `form_input` が効かない。
**クリック → 文字を type → 候補をクリック**で選ぶ。

`Continue to summary` で
`<アカウント名>'s Account - Cloudflare Pages:Edit` の 1 行だけが出ることを確認してから
`Create Token`。余計な行があれば戻る。

## 5. トークンを画面に出さずに Secrets へ流す (最重要)

トークンは**作成直後の 1 回しか表示されない**。そして
**エージェントの文脈・トランスクリプトに平文を残してはいけない**。
スクリーンショットも `get_page_text` も撮らずに、コピーボタンだけを押す。

コピーボタンの座標を知るのに全画面スクショを撮ると値が写る。
`read_page` の `filter: "interactive"` を使う — **値を含まずに ref だけ**返る。
トークン欄のコピーボタンと、下にある検証用 curl スニペットの
「Copy code to clipboard」の 2 つがあるので取り違えに注意する。

コピーしたら、**1 回の Bash 呼び出しで**登録まで完結させる
(シェル変数は Bash 呼び出しをまたいで残らない)。

```bash
pbpaste | gh secret set CLOUDFLARE_API_TOKEN -R <owner>/<repo>
printf '%s' '<ACCOUNT_ID>' | gh secret set CLOUDFLARE_ACCOUNT_ID -R <owner>/<repo>
gh secret list -R <owner>/<repo>
```

登録が終わったらクリップボードを消す。

```bash
printf '' | pbcopy
```

### やってはいけない: 「形だけ」確認するつもりで先頭を出す

クリップボードの中身が本当にトークンかを確かめたくなるが、
**先頭 N 文字を echo するのは失敗**。実体験でこれをやり、12 文字を露出させた。

正しくは長さと正規表現の**真偽だけ**を出す。中身は一切出さない。

```bash
v=$(pbpaste)
printf 'length=%s\n' "${#v}"
printf '%s' "$v" | grep -Eq '^cfut_[A-Za-z0-9_.-]+$' && echo "shape=ok" || echo "shape=unexpected"
```

### トークンの形式は 2 つある

| 形式 | 例 | 備考 |
|---|---|---|
| 旧 | 40 文字 `[A-Za-z0-9_-]{40}` | 世の中のスニペットはこれ前提 |
| 新 | `cfut_` プレフィックス + 全長 53 文字 | 2026 年時点の User API Token |

**`{40}` で検証すると新形式を「トークンではない」と誤判定する。**
`cfut_` は User API Token のプレフィックス。Account API Token は別。

## 6. 検証する (自己申告しない)

2 つ叩く。1 つ目はトークンの生死、2 つ目は**そのアカウントに対する Pages 権限**。
1 つ目だけでは権限のスコープが確認できない。

```bash
T=$(pbpaste); ACC=<ACCOUNT_ID>

curl -sS "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $T" | sed -E 's/"id":"[^"]*"/"id":"<redacted>"/g'

curl -sS -o /tmp/cfpages.json -w 'http_status=%{http_code}\n' \
  "https://api.cloudflare.com/client/v4/accounts/$ACC/pages/projects" \
  -H "Authorization: Bearer $T"
python3 -c "import json;d=json.load(open('/tmp/cfpages.json'));print('success=',d['success']);print('errors=',d['errors']);print('project_count=',len(d.get('result') or []))"
rm -f /tmp/cfpages.json
```

期待する出力:

```
{"result":{"id":"<redacted>","status":"active"},"success":true,...}
http_status=200
success= True
errors= []
```

`verify` のレスポンスには**トークン ID が入る**ので `sed` で潰してから貼る。
`project_count=0` は正常 (まだプロジェクトが無いだけ)。**403 なら権限のスコープが違う。**

一連は [templates/setup-cf-secrets.sh](templates/setup-cf-secrets.sh) にまとめてある。

## 7. ワークフロー側

`wrangler` は依存に足さず、メジャーを固定した `npx` でワークフロー内から呼ぶ。
CI でしか使わないものを全員の `npm ci` に載せない。

```yaml
- run: npx wrangler@4 pages deploy <dir> --project-name=<name>
  env:
    CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
    CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
```

public リポジトリでは **fork からの PR を対象にしない**。fork PR に Secrets は渡らず、
渡すには `pull_request_target` が必要で、これは未検証コードに認証情報を晒す既知の危険
パターン。ジョブ側で弾く。

```yaml
if: github.event.pull_request.head.repo.full_name == github.repository
```

Secrets 未登録のときは**デプロイを試みず、理由を出力して終了する**。
黙って緑にしない。

## 落ち穂

- 同一ブラウザで複数の Cloudflare アカウントを持つことになる。以降の操作は
  **Account ID で対象を確認する**。アカウント名 (`<メール>'s Account`) は似て見える
- 無料プランはカード登録不要。支払い情報を求められたらプランの選択を間違えている
- メール確認が未完でも Pages API は通る (2026-08 実測)。確認メールのリンクは
  後から踏めばよく、ブロッカーにしない
