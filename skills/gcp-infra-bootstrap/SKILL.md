---
name: gcp-infra-bootstrap
description: >-
  個人プロジェクトのバックエンドインフラ (GCPプロジェクト作成・Cloud Run・Google OAuth
  クライアント・Neon Postgres) を人間作業ゼロ〜最小限で立ち上げる手順。gcloud再認証の
  検知、専用GCPプロジェクトの新規作成 (既存の案件プロジェクトを汚さない)、
  OAuth同意画面/クライアントID作成のブラウザ自動操作代行、クライアントシークレットや
  リフレッシュトークンを画面に出さず安全に.envへ取り込む方法、Cloud Runの
  --allow-unauthenticated確認などを含む。「インフラ整備して」「GCPプロジェクト作って」
  「OAuthクライアント作って」「Cloud Runにデプロイして」等で使う。
origin: user
---

# GCPインフラ立ち上げ (人間作業最小化)

個人開発アプリの典型構成 (iOS/Web クライアント → Cloud Run バックエンド → Neon Postgres +
Google Drive) を、人間の手作業を極小に圧縮して構築する手順。[blueberry](../../..)
プロジェクトでの実施経験がベース。

## 全体の担当分け

| 作業 | 担当 | 理由 |
|---|---|---|
| DB作成・スキーマ投入 | 🤖 Claude (Neon MCPがあれば) | API/MCPで完結 |
| `gcloud auth login` | 🧑 人間 | 対話ログイン(2FA/パスワード)は代行不可 |
| GCPプロジェクト作成・課金リンク・API有効化 | 🤖 Claude | `gcloud` CLIで完結 |
| OAuth同意画面・クライアントID作成の画面遷移 | 🤖 Claude (claude-in-chrome) | UI操作はブラウザ自動操作で代行できる |
| Googleログインのパスワード入力 | 🧑 人間 | 本人確認は代行不可 |
| OAuthの「許可」クリック (実際のデータアクセス許諾) | 🧑 人間 | 実データへの同意は本人がやるべき一線 |
| Cloud Runデプロイ・env設定 | 🤖 Claude | `gcloud run deploy`で完結 |
| `--allow-unauthenticated`の可否判断 | 🧑 人間に確認 | 公開設定なのでサンドボックスが自動承認をブロックする |

## 1. gcloud再認証の検知

`gcloud services enable` 等が `Reauthentication failed` で失敗したら、以下を人間に依頼する:

```
! gcloud auth login
```

`!`付きで入力してもらうとセッション内で実行され、結果がそのまま見える。
このコマンドはブラウザでのログインを要求するため対話操作が必須 — 待つしかない。

## 2. 専用GCPプロジェクトを新規作成する

既存の案件プロジェクト (クライアント案件など) を流用しない。理由: 課金・権限・削除のしやすさが
分離でき、個人アプリの実験的インフラと本業の請求を混ぜない。

```bash
gcloud projects create <project-id> --name="<表示名>" --account=<メール>
gcloud config set project <project-id> --account=<メール>

# 課金アカウント確認 → リンク (Cloud Run等の有料APIにはほぼ必須)
gcloud billing accounts list --account=<メール>
gcloud billing projects link <project-id> --billing-account=<ACCOUNT_ID> --account=<メール>

gcloud services enable run.googleapis.com drive.googleapis.com iam.googleapis.com \
  cloudbuild.googleapis.com artifactregistry.googleapis.com \
  --project=<project-id> --account=<メール>
```

## 3. OAuth同意画面・クライアントID作成 (ブラウザ自動操作)

`gcloud alpha/iap oauth-brands` は非推奨かつIAP専用で一般用途に使えない。
Google Auth Platform (新UI) はUI操作のみが正式な作成経路 — ここを claude-in-chrome で代行する。

手順は [templates/oauth-console-steps.md](templates/oauth-console-steps.md) に画面ごとの
URLと操作を記載。要点:

1. `https://console.cloud.google.com/auth/overview/create?project=<id>` → アプリ情報・対象
   (外部/テスト)・連絡先・ポリシー同意の4ステップウィザード
2. `https://console.cloud.google.com/auth/audience?project=<id>` でテストユーザー追加
   (「外部」+テストモードの間はテストユーザーのみアクセス可)
3. `https://console.cloud.google.com/auth/scopes?project=<id>` で使うスコープ (例:
   `drive.file`) を「スコープを追加または削除」→ フィルタ検索 → チェック → 更新
4. `https://console.cloud.google.com/auth/clients/create?project=<id>` でクライアント作成
   (種類: デスクトップアプリ / ウェブアプリケーション等、用途に合わせる)

ログイン画面でパスワード入力を求められたら、そこだけ人間に「入力してください」と頼んで待つ
(`get_page_text`でログイン画面かどうか判定できる)。

## 4. クライアントシークレットを安全に.envへ取り込む (最重要ハマりどころ)

新しいGoogle Cloud ConsoleのUIでは **クライアントシークレットは作成直後の1回しか平文表示
されない**。スクリーンショットで読もうとすると小さすぎて誤読するか、ダイアログが
閉じて失われる。

**正しい手順**: 作成直後にダイアログの「ダウンロード」ボタン (⬇アイコン) をクリックし、
`~/Downloads/client_secret_*.json` を取得 → `jq`で値を抜き出して直接`.env`に書き込み、
**一度も画面 (tool出力) に生の値を表示しない**:

```bash
JSON_PATH=$(find ~/Downloads -newermt "<作成した時刻>" -name "client_secret*.json" -type f | head -1)
{
  echo "GOOGLE_CLIENT_ID=\"$(jq -r '.installed.client_id' "$JSON_PATH")\""
  echo "GOOGLE_CLIENT_SECRET=\"$(jq -r '.installed.client_secret' "$JSON_PATH")\""
} >> .env
shred -u "$JSON_PATH" 2>/dev/null || rm -f "$JSON_PATH"
```

`cat`でJSONの中身をそのまま出力するとサンドボックスの資格情報保護ルールにブロックされる
(意図通りの安全装置)。**シェル変数はBashツール呼び出しをまたいで保持されない**ので、
「JSON抽出→.env書き込み→シークレットファイル削除」は必ず**1回のBash呼び出し内**で
アトミックに完結させること。分割すると値を失って作り直しになる (実体験: 2回シークレットを
無駄に発行し直した)。

クライアントシークレットは1クライアントにつき**最大2枠**。3つ目が必要なら既存を
「無効にする」→「削除」してから追加する。

## 5. リフレッシュトークン取得 (人間の同意クリックは代替しない)

Driveなど実データへのOAuthスコープを要求する「許可」画面は、たとえブラウザ自動操作の
権限をもらっていても **人間に実際にクリックしてもらう**。理由: これは実データへの
アクセス許諾そのものであり、UI操作代行の合意範囲を超える一線。

```bash
set -a; source .env; set +a
nohup pnpm get-refresh-token > /tmp/get-refresh-token.log 2>&1 &
sleep 4
cat /tmp/get-refresh-token.log   # 認可URLが出る (これはURLなので表示してよい)
```

認可URLを人間に渡して「開いて許可してください」と依頼 → 完了報告を待つ →
ログファイルからトークン行だけを抽出して直接`.env`へ書き込み、ログファイルは削除:

```bash
REFRESH_TOKEN=$(grep -A1 "^GOOGLE_REFRESH_TOKEN:$" /tmp/get-refresh-token.log | tail -1)
python3 -c "
import re
with open('.env') as f: lines = f.readlines()
with open('.env','w') as f:
    for l in lines:
        f.write(f'GOOGLE_REFRESH_TOKEN=\"$REFRESH_TOKEN\"\n' if l.startswith('GOOGLE_REFRESH_TOKEN=') else l)
"
shred -u /tmp/get-refresh-token.log 2>/dev/null || rm -f /tmp/get-refresh-token.log
```

## 6. Cloud Runデプロイ

```bash
set -a; source .env; set +a
gcloud run deploy <service> --source . --project=<id> --region=<region> \
  --allow-unauthenticated --max-instances=1 \
  --set-env-vars="API_TOKEN=${API_TOKEN},DATABASE_URL=${DATABASE_URL},..." \
  --account=<メール>
```

ハマりどころ:

- **初回ビルドは2分のBashデフォルトタイムアウトを超えることが多い** → `nohup ... &` で
  バックグラウンド実行し、`Monitor`ツールで `Service URL|ERROR` をgrepして完了を待つ
  (ポーリングでsleepループを自分で書かない)。
- **`--allow-unauthenticated` はサンドボックスの自動承認ルールでブロックされる**
  (「公開設定を人間の明示的同意なしに変更した」と判定される)。個人アプリでクライアント側が
  IAMトークンを持たず、代わりにアプリ層のBearerトークン (`API_TOKEN`) で保護する設計なら
  正当な選択だが、**必ず一度AskUserQuestionで確認してから**実行する。
- `.env`の値を`source`する前に、値に`&`や特殊文字 (接続文字列のクエリパラメータ等) が
  含まれる場合は各行をダブルクオートで囲むこと。囲まないと`source`が`&`をバックグラウンド
  ジョブ区切りと誤解してパースエラーになる。

## 7. DRIVE_FOLDER_ID等、実行時にしか分からない値の後追い設定

初回リクエストでのみ`console.info`されるようなIDは、デプロイ後にログを引いて確定させ、
再デプロイする:

```bash
gcloud run services logs read <service> --project=<id> --region=<region> --limit=50 \
  | grep "folder ID"
gcloud run services update <service> --project=<id> --region=<region> \
  --update-env-vars="DRIVE_FOLDER_ID=<取得した値>"
```
