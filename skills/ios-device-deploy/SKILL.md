---
name: ios-device-deploy
description: >-
  iOS実機へのCLIビルド配信の手順書。特にXcodeアカウントが使えない状況 (トークン切れ・CI) で、
  既存プロビジョニングプロファイルを借用してリサイン配信する方法と、プロジェクト用
  deploy-device.sh の雛形を提供する。「実機にビルドして」「デバイスに配信」「devicectlで
  インストール」「署名エラーで実機に入らない」等の場面、および新しいiOSプロジェクトで
  配信スクリプトを整備するときに使う。
origin: user
---

# iOS 実機配信 (CLI / リサイン方式)

Xcode GUI を使わず、コマンドラインだけで iOS 実機にビルドを配信する手順。
ルール [swift/deployment.md](../../rules/swift/deployment.md) の「how」側。

## 前提の確認

```bash
xcrun devicectl list devices        # 対象デバイスが connected か (unavailable なら接続/ロック解除が必要)
security find-identity -v -p codesigning   # Apple Development 証明書があるか
```

## パターンA: 自動署名が使えるとき (最短)

Xcode にアカウントがサインイン済みなら、これだけでよい:

```bash
xcodebuild -scheme <Scheme> -destination 'platform=iOS,name=<デバイス名>' \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> <path/to/App.app>
```

`No Accounts` エラーが出る場合はアカウントトークンが無い → パターンBへ
(恒久対応は Xcode → Settings → Accounts でサインイン)。

## パターンB: プロファイル借用リサイン (アカウント不要)

自動プロビジョニングが使えなくても、**同じチームの有効なプロファイルが1つでも
ローカルにあれば**、そのバンドルIDを借用して配信できる。

### 手順

実行可能な雛形が [templates/deploy-device.sh](templates/deploy-device.sh) にある。
新しいプロジェクトでは:

```bash
cp <このスキルのディレクトリ>/templates/deploy-device.sh <プロジェクト>/deploy-device.sh
chmod +x deploy-device.sh
# 冒頭の「設定」6変数 (DEVICE_NAME / DEVICE_UDID / BUNDLE_ID / IDENTITY / SCHEME / APP_NAME) を埋める
```

雛形は プレースホルダ未記入ガード / 接続確認の早期失敗 / プロファイル自動探索 /
未署名Releaseビルド → 内部dylibから順にリサイン / ロック中の起動失敗許容 を実装済み。
処理の流れ: ①接続確認 → ②バンドルIDに合うプロファイル探索 → ③未署名Releaseビルド
→ ④プロファイル埋め込み+エンタイトルメント抽出+リサイン → ⑤devicectlでインストール+起動。

## ハマりどころ (実体験由来)

| 症状 | 原因と対処 |
|---|---|
| 起動直後に即クラッシュ、`dyld: Library not loaded ... .debug.dylib` | Debugビルドは本体が `.debug.dylib` に分離される。**Releaseでビルドする**か、内部dylibを先に署名する |
| `Xcode managed profile ... requires manually managed` | Xcode管理プロファイルは `PROVISIONING_PROFILE_SPECIFIER` で指定できない。上記の「未署名ビルド→後からリサイン」方式を使う |
| `devicectl` が `unavailable` / `Locked` | 未接続 or ロック中。Wi-Fi接続なら同一ネットワーク+ロック解除。インストールは成功していることが多い |
| 借用IDのアプリが上書きされる | 借用中は元のアプリと共存できない。ユーザーに明示しておく |
| Bashサンドボックスで codesign/keychain が失敗 | 署名・devicectl はサンドボックス無効で実行する必要がある |

## 注意

- 借用方式は**開発検証用**。配布には正規のバンドルID+プロファイルを使う
- プロファイルとバンドルIDはユーザーの資産。借用は事前に説明し、恒久対応
  (Xcodeサインイン → 自動署名) への切替タイミングを提示すること
