---
paths:
  - "**/*.swift"
  - "**/project.yml"
  - "**/*.xcodeproj/**"
---
# Swift / iOS Deployment

> This file extends [common/deployment.md](../common/deployment.md) with iOS-specific content.

## Real-Device Delivery After Every Change

iOS のプロジェクトでは、ユーザーの検証面はほぼ常に**実機**である。
コードを修正したら、シミュレータでのテスト (`xcodebuild ... test`) を通した後、
リポジトリの配信スクリプト (例: `deploy-device.sh`) で実機へビルドを届けること。

```bash
xcodebuild -project App.xcodeproj -scheme App -destination '<simulator>' test  # 1. テスト
./deploy-device.sh                                                             # 2. 実機配信
```

## 配信スクリプトの要件

各リポジトリの配信スクリプトは以下を満たすこと:

1. **接続確認を最初に行う** — 端末未接続なら分かりやすいエラーで早期失敗
   (`xcrun devicectl list devices` で state を確認)
2. **1コマンドで完結** — ビルド → 署名 → `devicectl device install app` → 起動まで
3. **ビルド失敗を握りつぶさない** — `xcodebuild` の終了コードで判定し、失敗時はログ末尾を表示
4. **端末ロック中の起動失敗は許容** — インストール成功なら「アイコンから起動」と案内

## 署名の2パターン

- **通常**: 自動署名 (`CODE_SIGN_STYLE=Automatic` + `DEVELOPMENT_TEAM`)。
  Xcode にアカウントがサインイン済みならこれだけでよい
- **アカウントが使えないとき** (トークン切れ・CI等): 既存プロビジョニング
  プロファイルを借用したリサイン方式が使える。手順はスキル
  **`ios-device-deploy`** を参照 (未署名ビルド → プロファイル埋め込み →
  エンタイトルメント抽出 → 内部dylibから順に codesign)

## プロジェクト側に書くこと

`CLAUDE.md` に「修正後は必ず `./deploy-device.sh`」の一文と、対象デバイス名・
署名方式の背景を明記する。デバイスUDID・借用バンドルID等の固有値はスクリプト内に置く。
