# Google Auth Platform 画面操作メモ (claude-in-chrome用)

新UI (`console.cloud.google.com/auth/...`) はSPAで、直接URL遷移すると
「プロジェクトが選択されていません」と表示されることがある。その場合は左上の
プロジェクトセレクタ (ヘッダーの現在のプロジェクト名ボタン) を一度クリックして
選択し直すと復帰する。

## 同意画面ウィザード (初回のみ)

`https://console.cloud.google.com/auth/overview/create?project=<id>`

1. **アプリ情報**: アプリ名を入力 → ユーザーサポートメールのコンボボックスをクリック →
   候補 (自分のメール) をクリック → 「次へ」
2. **対象**: 個人利用なら「外部」を選択 (内部はGoogle Workspace組織のみ) → 「次へ」
3. **連絡先情報**: デベロッパー連絡先メールを入力 → 「次へ」
4. **終了**: ポリシー同意チェックボックス → 「作成」

作成後は数秒処理中になり、`auth/overview` にリダイレクトされる。

## テストユーザー追加

`https://console.cloud.google.com/auth/audience?project=<id>`

「テストユーザー」セクションまでスクロール → 「Add users」→ テキストボックスに
メールアドレスを入力してEnter (チップ化される) → 「保存」。

## スコープ追加

`https://console.cloud.google.com/auth/scopes?project=<id>`

「スコープを追加または削除」→ 開いたパネル上部のフィルタ欄にスコープ名の一部
(例 `drive.file`) を入力 → 候補行が絞り込まれる → 行頭のチェックボックスをクリック →
下部の「更新」。有効化されていないAPIのスコープは一覧に出ないので、先に
`gcloud services enable <api>.googleapis.com` で有効化しておく。

## クライアントID作成

`https://console.cloud.google.com/auth/clients/create?project=<id>`

1. 「アプリケーションの種類」ドロップダウン → 用途に応じて選択
   (Desktopアプリのローカルスクリプト経由OAuthなら「デスクトップ アプリ」)
2. 「名前」を分かりやすく変更 (例: `<service>-backend`)
3. 「作成」→ 直後にID/シークレットのダイアログが出る

**この直後のダイアログを逃すとシークレットは二度と平文表示できない。**
`get_page_text`ではダイアログ内容が取れないことがあるので、必ず
「⬇ (ダウンロード)」アイコンをクリックしてJSONを保存し、SKILL.md本文の手順で
`jq`抽出する。ダイアログを閉じてしまった場合は、クライアント詳細ページの
(i) アイコン → 「クライアント シークレット」→「Add secret」で新規発行できる
(1クライアントにつき最大2枠)。
