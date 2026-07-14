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

### 手順 (deploy スクリプトの雛形)

```bash
#!/bin/bash
set -euo pipefail
DEVICE_UDID="<devicectl list devices のUDID>"
BUNDLE_ID="<借用するバンドルID>"          # プロファイルが存在するID
IDENTITY="Apple Development: <名前> (<ID>)"  # security find-identity の表記
DERIVED="${TMPDIR:-/tmp}/device-build"

# 0. 接続確認 (早期失敗)
xcrun devicectl list devices | grep -q "<デバイス名>.*connected" || { echo "未接続"; exit 1; }

# 1. バンドルIDに合うプロファイルを探す
PROFILE=""
for f in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.mobileprovision; do
  security cms -D -i "$f" 2>/dev/null | grep -q "$BUNDLE_ID" && { PROFILE="$f"; break; }
done
[ -n "$PROFILE" ] || { echo "プロファイルなし"; exit 1; }

# 2. 未署名で Release ビルド (終了コードで成否判定)
xcodebuild -scheme <Scheme> -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" build \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" CODE_SIGNING_ALLOWED=NO
APP="$DERIVED/Build/Products/Release-iphoneos/<App>.app"

# 3. プロファイル埋め込み → エンタイトルメント抽出 → リサイン
cp "$PROFILE" "$APP/embedded.mobileprovision"
security cms -D -i "$PROFILE" > /tmp/profile.plist
plutil -extract Entitlements xml1 -o /tmp/ent.plist /tmp/profile.plist
find "$APP" -name "*.dylib" -exec codesign --force --sign "$IDENTITY" {} \;   # 内部Mach-Oを先に!
codesign --force --sign "$IDENTITY" --entitlements /tmp/ent.plist "$APP"
codesign --verify --strict "$APP"

# 4. インストール + 起動 (ロック中は起動だけ失敗する → 案内して成功扱い)
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"
xcrun devicectl device process launch --device "$DEVICE_UDID" "$BUNDLE_ID" \
  || echo "端末ロック中。アイコンから起動してください"
```

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
