---
name: workers-fetch-user-agent-403
description: >-
  Cloudflare Workers (workerd) の fetch から外部 API を呼ぶと 403 + HTML が返るのに、
  同じキーで curl や Node の fetch は 200 になる、という症状の切り分け手順と最小修正。
  原因は workerd の fetch が User-Agent を一切付けないことで、CloudFront / AWS WAF /
  一部 WAF は User-Agent 不在のリクエストを認証 (API キー検証) の手前で弾く。
  「Worker 経由だけ 403」「上流が HTML の 403 を返す」「API Proxy が 502 になる」
  「curl は通るのに Worker は通らない」等で使う。秘密鍵を一度も画面に出さずに
  検証する curl / wrangler の回し方と、zsh の `path` 変数で PATH が壊れるハマりも含む。
origin: user
---

# Workers の fetch だけ上流が 403 + HTML になる

## 症状

- Cloudflare Worker の API Proxy から上流 API を叩くと **403、Content-Type: text/html**。
  Proxy は 502 を返す。`wrangler dev --local` でも `--remote` でも本番でも同じ。
- 同じ API キーで `curl` も Node 標準 `fetch` も **200 + JSON**。
- 上流の公式仕様では「403 = キーが無い／無効」としか書かれていないので、
  キーの読み込み (`.dev.vars`、Secret binding) を疑って時間を溶かしやすい。

## 原因

**workerd の `fetch` は既定で `User-Agent` ヘッダーを付けない** (curl は `curl/x.y`、
Node/undici は `node` を付ける)。上流が CloudFront (+ AWS WAF の
`NoUserAgent_HEADER` 相当) や同種の WAF の背後にあると、User-Agent 不在の
リクエストは **API Gateway / オリジンに届く前に CloudFront が 403 の HTML** で弾く。
認証エラーの 403 とは別物で、見分けるポイントは応答ヘッダー:

| 層 | 403 の Content-Type | 付くヘッダー |
|---|---|---|
| CloudFront / WAF で拒否 | `text/html` | `server: CloudFront`、`x-cache: Error from cloudfront`、**`x-amzn-requestid` 無し** |
| API Gateway でキー不正 | `text/plain` or JSON | `x-amzn-requestid` **有り** |

`cf-mitigated: challenge` は付かない (Cloudflare 側のチャレンジではない)。

## 切り分け手順 (キーを画面に出さない)

### 1. キー無しで User-Agent の有無だけ変えて叩く (秘密不要・最速)

```sh
U=https://<upstream-host>/<path>
show() { echo "### $1"; shift
  curl -sS -o /dev/null -D - "$@" "$U" | tr -d '\r' \
    | grep -iE '^(HTTP/|content-type|server|x-cache|x-amzn-requestid)'; echo; }
show "defaults"            # 403 text/plain + x-amzn-requestid → オリジン到達
show "no UA" -H 'User-Agent:'   # 403 text/html + server: CloudFront → 手前で拒否
show "no Accept" -H 'Accept:'   # Accept は無関係なことも確認
```

`-H 'User-Agent:'` (値なし) で curl のデフォルト UA を**削除**できる。
ここで応答の種類が変われば、キーではなく UA が原因と判る。

### 2. 本物のキーで同じ行列を回す (キーをコマンド引数に載せない)

```sh
umask 077; HF=$(mktemp)
# .dev.vars から値だけ取り出し、curl のヘッダーファイルへ (echo しない)
KEY=$(sed -nE 's/^[[:space:]]*YUMEMI_API_KEY[[:space:]]*=[[:space:]]*//p' .dev.vars \
      | head -1 | tr -d '\r' | sed -E 's/^"(.*)"$/\1/')
echo "key present: $([ -n "$KEY" ] && echo true || echo false), length: ${#KEY}"
printf 'X-API-KEY: %s\n' "$KEY" > "$HF"; unset KEY
curl -sS -o /dev/null -w '%{http_code} %{content_type}\n' -H @"$HF" "$U"                     # 200
curl -sS -o /dev/null -w '%{http_code} %{content_type}\n' -H @"$HF" -H 'User-Agent:' "$U"    # 403 html
curl -sS -o /dev/null -w '%{http_code} %{content_type}\n' -H @"$HF" -H 'User-Agent: my-proxy' "$U"  # 200
rm -f "$HF"
```

出力は status / content-type / 存在 boolean / 長さ に限定する。

### 3. workerd で再現・修正検証 (`.dev.vars` をコピーしない)

`wrangler dev` の `--env-file` で既存の `.dev.vars` を**その場所のまま**読ませる。
UA あり／なしを 1 回のリクエストで比較する使い捨て Worker をスクラッチ領域に置く:

```js
// probe/worker.mjs
async function probe(headers) {
  const r = await fetch(UPSTREAM, { method: 'GET', headers, redirect: 'manual',
    signal: AbortSignal.timeout(10_000) })
  await r.body?.cancel()
  return { status: r.status, type: r.headers.get('content-type')?.split(';')[0],
    reachedOrigin: r.headers.has('x-amzn-requestid'), server: r.headers.get('server') }
}
export default { async fetch(_req, env) {
  const key = env.YUMEMI_API_KEY
  return Response.json({
    withoutUA: await probe({ 'X-API-KEY': key }),
    withUA:    await probe({ 'X-API-KEY': key, 'User-Agent': 'my-proxy' }),
  }) } }
```

```sh
pnpm exec wrangler dev --config probe/wrangler.jsonc --env-file path/to/.dev.vars \
  --local --ip 127.0.0.1 --port 8791 &   # --remote でも同じ結果になることを確認
curl -sS http://127.0.0.1:8791/
```

`--remote` は本人の Cloudflare 認証で同名 Worker の**一時 preview** を作るだけで、
本番 deployment や Secret は更新しない。

## 最小修正

上流への fetch に、**プロキシ自身を名乗る固定の User-Agent** を 1 つ足す。

```ts
// config.ts
// 上流のCloudFrontはUser-Agentが無いリクエストをAPIキー検証の手前で403・HTMLとして拒否する。
// workerdのfetchは既定でUser-Agentを付けないため、プロキシ自身を名乗る固定値を送る。
export const upstreamUserAgent = '<project>-proxy'

// index.ts
fetch(url, { method: 'GET',
  headers: { 'X-API-KEY': apiKey, 'User-Agent': upstreamUserAgent },
  redirect: 'manual', signal })
```

- ブラウザや curl を**騙る UA にしない**。自分の名前を名乗るのは「不在ヘッダーを
  補う」だけで、アクセス制限の偽装・回避ではない。
- テストは `fetch` の呼び出し引数を `toHaveBeenCalledExactlyOnceWith` で固定しているはず
  なので、`headers` に UA を追加 (RED) → 実装 (GREEN)。
- 既存 Worker が `diagnostic.responseType` (JSON / HTML / OTHER) を記録していれば、
  本番ログで `status: 403, responseType: 'HTML'` を見た時点でこのスキルを疑う。

## ハマりどころ

- **zsh で `for path in ...` と書くと PATH が壊れる**。`path` は zsh では PATH と
  連動する特殊配列。ループ変数は `apiPath` 等にする。症状は突然の
  `command not found: curl`。
- `WRANGLER_LOG_PATH=/dev/null` は wrangler がディレクトリとして mkdir しようとして
  `EEXIST` を吐く (動作には影響なし)。一時ディレクトリを渡すほうが静か。
- `ls -la .dev.vars* .env*` のように存在しない glob を混ぜると zsh は
  `no matches found` でコマンド全体を中断し、存在するほうも表示されない。
  `setopt null_glob` か個別に確認する。
- 403 だけで WAF と断定しない。上記表のヘッダーで「どの層が返した 403 か」を
  先に確定してから結論を出す。
