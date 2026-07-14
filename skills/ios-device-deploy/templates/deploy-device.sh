#!/bin/bash
# iOS実機へのビルド+配信テンプレート (ios-device-deploy スキル付属)。
#
# 使い方: プロジェクト直下に cp して、下の「設定」4変数を埋める。
# Xcodeアカウントが使えない環境向けの「プロファイル借用リサイン」方式
# (通常の自動署名が使えるなら SKILL.md のパターンAの方が簡単)。
#
# 実戦投入済みの元実装: t2421/prototyping の deploy-device.sh
set -euo pipefail
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")"

# ===== 設定 (プロジェクトごとに埋める) =====
DEVICE_NAME="<devicectl list devices に出るデバイス名>"
DEVICE_UDID="<同コマンドの Identifier>"
BUNDLE_ID="<借用するバンドルID (有効なプロファイルが存在するもの)>"
IDENTITY="<security find-identity -v -p codesigning の表記 例: Apple Development: Name (XXXXXXXXXX)>"
SCHEME="<Xcodeスキーム名>"
APP_NAME="<生成される .app 名 (拡張子なし)>"
# ==========================================

if grep -q '^\(DEVICE_NAME\|DEVICE_UDID\|BUNDLE_ID\|IDENTITY\|SCHEME\|APP_NAME\)="<' "$SELF"; then
    echo "ERROR: テンプレートの設定変数を埋めてから実行してください" >&2
    exit 1
fi

DERIVED="${TMPDIR:-/tmp}/${SCHEME}-device-build"
LOG="$DERIVED/build.log"

# 0a. 並行実行ロック (derivedDataや署名途中appの共有は壊れたビルドを生む)
LOCK="$DERIVED.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    echo "ERROR: 別の deploy が実行中です ($LOCK が存在)。完了を待つか、残骸なら rmdir してください" >&2
    exit 1
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# 0b. デバイス接続確認 (State列の完全一致。"disconnected" への部分一致を防ぐ)
if ! xcrun devicectl list devices 2>/dev/null | awk -v name="$DEVICE_NAME" '$1==name && $4=="connected" {found=1} END {exit !found}'; then
    echo "ERROR: $DEVICE_NAME が接続されていません (USB接続 or 同一Wi-Fi+ロック解除が必要)" >&2
    exit 1
fi

# 1. バンドルIDに合う「有効期限内の」プロビジョニングプロファイルを探す
PROFILE=""
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
for f in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.mobileprovision; do
    security cms -D -i "$f" 2>/dev/null > "${TMPDIR:-/tmp}/deploy-profile-check.plist" || continue
    grep -q "$BUNDLE_ID" "${TMPDIR:-/tmp}/deploy-profile-check.plist" || continue
    EXPIRY="$(plutil -extract ExpirationDate raw "${TMPDIR:-/tmp}/deploy-profile-check.plist" 2>/dev/null || echo "")"
    if [ -n "$EXPIRY" ] && [ "$EXPIRY" \< "$NOW" ]; then
        echo "WARN: 期限切れプロファイルをスキップ: $(basename "$f")" >&2
        continue
    fi
    PROFILE="$f"
    break
done
if [ -z "$PROFILE" ]; then
    echo "ERROR: $BUNDLE_ID のプロビジョニングプロファイルが見つかりません" >&2
    exit 1
fi

# 2. 未署名でReleaseビルド (Debugは .debug.dylib 分離で起動不能になるため必ずRelease)
mkdir -p "$DERIVED"
if ! xcodebuild -scheme "$SCHEME" -configuration Release \
        -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" build \
        PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" CODE_SIGNING_ALLOWED=NO > "$LOG" 2>&1; then
    echo "ERROR: ビルド失敗。ログ末尾:" >&2
    tail -20 "$LOG" >&2
    exit 1
fi
echo "BUILD SUCCEEDED"

APP="$DERIVED/Build/Products/Release-iphoneos/$APP_NAME.app"

# 3. プロファイル埋め込み + エンタイトルメント抽出 + リサイン
#    (内部Mach-Oを先に署名しないと起動時にdyldが拒否する)
ENT_DIR="$(mktemp -d)"
trap 'rm -rf "$ENT_DIR"' EXIT
security cms -D -i "$PROFILE" > "$ENT_DIR/profile.plist"
plutil -extract Entitlements xml1 -o "$ENT_DIR/ent.plist" "$ENT_DIR/profile.plist"
cp "$PROFILE" "$APP/embedded.mobileprovision"
find "$APP" -name "*.dylib" -exec codesign --force --sign "$IDENTITY" {} \;
codesign --force --sign "$IDENTITY" --entitlements "$ENT_DIR/ent.plist" "$APP"
codesign --verify --strict "$APP"
echo "SIGN OK"

# 4. インストール + 起動 (起動は端末ロック中だと失敗するが、インストール済みなら成功扱い)
if ! xcrun devicectl device install app --device "$DEVICE_UDID" "$APP" > "$DERIVED/install.log" 2>&1; then
    echo "ERROR: インストール失敗。ログ末尾:" >&2
    tail -5 "$DERIVED/install.log" >&2
    exit 1
fi
echo "INSTALL OK"
if xcrun devicectl device process launch --device "$DEVICE_UDID" "$BUNDLE_ID" > /dev/null 2>&1; then
    echo "LAUNCH OK — $DEVICE_NAME で起動しました"
else
    echo "LAUNCH SKIPPED — 端末ロック中の可能性。ホーム画面のアイコンから起動してください"
fi
echo "DEPLOYED to $DEVICE_NAME"
