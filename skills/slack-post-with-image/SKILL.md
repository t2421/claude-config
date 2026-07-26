---
name: slack-post-with-image
description: >-
  Slack にスクリーンショット等の画像を添付して投稿する手順。「slack に送っといて」
  「このキャプチャを共有して」「#チャンネル に画像を貼って」等の依頼で使う。
  Slack MCP には画像アップロード用ツールが無いためブラウザ操作が必須で、その過程で
  踏むハマりどころ (ドメイン別権限・アップロード可能パスの制限・入力欄が追記しか
  受け付けない・# がチャンネル補完に食われる) と回避策をまとめている。
origin: user
---

# Slack へ画像付きで投稿する

## 最初に判断すること

**テキストだけで足りるなら MCP で完結する。画像添付が必要な時だけブラウザ操作へ。**

| やりたいこと | 手段 |
|---|---|
| テキスト投稿・スレッド返信・予約投稿・下書き | Slack MCP (`slack_send_message` 等) |
| **画像・ファイルの添付** | **ブラウザ操作 (Claude in Chrome)** |

Slack MCP (claude.ai Slack コネクタ) が持つのは送信・検索・読み取り・キャンバス系のみで、
**ファイルアップロード用のツールが存在しない**。`+slack upload` 等で ToolSearch しても出てこない。

## 事前確認

```bash
claude mcp list          # "claude.ai Slack ... ✔ Connected" を確認
```

> Connected なのにツールが見つからない場合、**コネクタ有効化がセッション開始より後**の可能性が高い。
> ツール一覧はセッション開始時に確定するため、こちらから再読込できない。`/mcp` 再接続か
> セッション再起動をユーザーに依頼する。

## 手順

### 1. チャンネル ID を引く (MCP)

```
slack_search_channels(query: "<channel-name>", response_format: "concise")
→ #<channel-name> (C0XXXXXXX)
```

### 2. 画像を用意する

`upload_image`（imageId 指定）は **"Unable to access message history to retrieve image" で失敗する**。
`file_upload`（パス指定）を使うが、**任意パスは拒否される**:

> only files this session is allowed to read can be uploaded

`/var/folders/.../claude-chrome-screenshots-*/` に保存されたスクリーンショットも**対象外**。
**セッションの scratchpad にコピーしてから** 渡すこと。

```bash
cp "<screenshot-path>" "$SCRATCHPAD/<meaningful-name>.jpg"
```

スクリーンショットは投稿するセッションで撮り直すのが確実。トーストのような短命な UI は
`browser_batch` で `click → wait 2 → screenshot` を1回にまとめないと取り逃す。

### 3. チャンネルを開く

```
navigate → https://slack.com/app_redirect?channel=<CHANNEL_ID>
```

**`<workspace>.slack.com` と `app.slack.com` は Claude in Chrome の権限上は別ドメイン。**
片方を許可しても、リダイレクト後にもう一方で `Permission denied for this action on this domain`
が出る。両方許可してもらう必要がある。

リダイレクトページで止まったら「open this link in your browser」をクリックして Web 版へ進む。

### 4. 画像を添付する

ファイル選択ボタン（`+`）は**クリックしない**。ネイティブのファイルダイアログが開くと操作不能になる。
隠しファイル入力を直接狙う。

```
find(query: "hidden file input element for uploading files")  → ref_N
file_upload(paths: ["<scratchpad path>"], ref: "ref_N")
```

添付するとコンポーザーの高さが変わり座標がずれる。**添付後に必ずスクリーンショットを取り直す。**

### 5. 本文を入力する

Slack のコンポーザー (Quill) には2つの罠がある。

**罠1: 追記しか受け付けない。** `cmd+A`・`Backspace`・triple-click からの上書きが
いずれも無反応で、`type` による追記だけが通る。一度壊れると手で直せない。
**入力前に JavaScript でクリアするのが確実。**

```js
const el = document.querySelector('[data-qa="message_input"] .ql-editor')
        || document.querySelector('.ql-editor[contenteditable="true"]');
el.focus();
const sel = window.getSelection(), range = document.createRange();
range.selectNodeContents(el); sel.removeAllRanges(); sel.addRange(range);
document.execCommand('delete');
```

**罠2: `#123` がチャンネル補完に食われる。** `PR #246` と打つと `#246` に補完が反応し、
**先頭側の文字列がごっそり消える**。`#` は使わず `PR 246` と書く。
`@` も同様にメンション補完を誘発するので避ける。

また、フォーカス直後の最初の `type` は先頭の ASCII 部分が落ちることがある。
**2回に分けて打ち、間に `wait` を挟み、スクリーンショットで実際の文字列を必ず確認する。**

### 6. 送信

送信は取り消せない。**押す直前にスクリーンショットで本文と添付を確認し、ユーザーの承認を得る。**
承認済みなら送信ボタンをクリックし、投稿後の画面も撮って結果を報告する。

## 落とし穴まとめ

| 症状 | 原因 | 対処 |
|---|---|---|
| Slack のアップロードツールが無い | MCP に未実装 | ブラウザ操作に切り替える |
| MCP は Connected なのにツールが出ない | セッション開始後に有効化された | `/mcp` 再接続かセッション再起動 |
| `Permission denied ... on this domain` | `*.slack.com` と `app.slack.com` が別扱い | 両方を拡張で許可 |
| `Unable to access message history` | `upload_image` の imageId 参照が不可 | `file_upload` + パス指定に切り替え |
| `only files this session is allowed to read` | 一時ディレクトリは許可外 | scratchpad にコピーしてから渡す |
| 本文が消える・重複する | Quill が追記しか受け付けない | JS の `execCommand('delete')` でクリア |
| 先頭の文字列が欠落する | `#` のチャンネル補完 / 初回 type の取りこぼし | `#` を使わない・分割入力・目視確認 |
| トーストが写らない | ラウンドトリップが表示時間より長い | `browser_batch` で click→wait→screenshot |

## やってはいけないこと

- ファイル選択ボタンのクリック（ネイティブダイアログでセッションが固まる）
- 確認なしの送信（取り消せない・チャンネル全員に見える）
- 同じ操作の繰り返しリトライ。2〜3回失敗したら原因を切り分けるか、ユーザーに手渡す
