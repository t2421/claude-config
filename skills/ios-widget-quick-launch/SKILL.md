# iOS ウィジェットからの即起動 (WidgetKit + ディープリンク)

「ホーム画面のウィジェットをタップ → アプリの特定画面を直接開く」を
XcodeGen プロジェクトで実装する手順と、実体験由来のハマりどころ。

## 構成 (3点セット)

1. **app-extension ターゲット** (XcodeGen `project.yml`):

   ```yaml
   targets:
     MyWidgets:
       type: app-extension
       platform: iOS
       sources:
         - MyWidgets
         # 本体と共有したいファイルはソース単位で追加 (下記「モジュール共有」)
         - path: App/DesignSystem/SharedShape.swift
       info:
         path: MyWidgets/Info.plist
         properties:
           CFBundleDisplayName: MyApp
           NSExtension:
             NSExtensionPointIdentifier: com.apple.widgetkit-extension
       settings:
         base:
           PRODUCT_BUNDLE_IDENTIFIER: com.example.app.widgets  # 本体IDのサフィックス
           GENERATE_INFOPLIST_FILE: false
           SKIP_INSTALL: true
   # 本体ターゲットに:
   #   dependencies: [{ target: MyWidgets, embed: true }]
   #   info.properties に CFBundleURLTypes で custom scheme を登録
   ```

2. **ウィジェット側**: `StaticConfiguration` + `.widgetURL(URL(string: "myapp://compose"))`。
   タイムラインは固定表示なら `policy: .never` の1エントリでよい。

3. **アプリ側**: `onOpenURL` で受けて対象画面を開く — ただし下記の罠を参照。

## ハマりどころ (実体験由来)

| 症状 | 原因と対処 |
|---|---|
| コールドローンチ時だけディープリンクが無視される | `onOpenURL` は**その瞬間ビューヒエラルキーに存在するモディファイアにしか配送されない**(キューされない)。認証チェック中のローディング画面やサインイン画面が出ている間に URL が届くと消える。→ 受信は常駐するルートビューに置き、`@Observable` なルーター(`pendingAction: Action?`)に保持。対象画面が `.task`(マウント時) + `.onChange`(起動中の再タップ) の両方で拾って消費する |
| ウィジェットが描画されず「containerBackground の採用が必要」表示 | iOS 17+ は**全ファミリーで** `.containerBackground(for: .widget) { ... }` 必須。`accessoryCircular` など分岐がある場合は**全分岐に**付ける (ロック画面系は `AccessoryWidgetBackground()`) |
| ウィジェットから本体のデザインシステムが使えない | App Extension は本体モジュールを import できない。→ 共有したい型は**依存のない単独ファイル**に切り出し、XcodeGen の `sources` に `path:` で両ターゲットに追加 (色トークン2〜3値程度なら複製 + 出典コメントでも可) |
| モックスキームでテストしてもディープリンクの罠に気づけない | モックモードが認証をスキップして対象画面を直接出す構成だと、コールドローンチ問題が再現しない。実機 or 通常スキームで「アプリをkill → ウィジェットタップ」を必ず確認 |

## ルーターの雛形

```swift
@MainActor @Observable
final class DeepLinkRouter {
    private(set) var pendingAction: DeepLinkAction?

    @discardableResult
    func open(_ url: URL) -> Bool {
        guard url.scheme == "myapp" else { return false }
        switch url.host() {
        case "compose": pendingAction = .compose; return true
        default: return false
        }
    }
    func consume(_ action: DeepLinkAction) {
        if pendingAction == action { pendingAction = nil }
    }
}
```

- 未サインインでタップされた場合も、サインイン完了 → 対象画面マウント時の
  `.task` が保持済みの意図を拾うので自然に繋がる
- URL 解釈が View から分離されるので単体テスト可能になる (scheme/host/消費のテストを書く)

## おまけ: 録音で他アプリの音楽を止めない

音声入力機能を持つアプリでの隣接ハマりどころ:
`AVAudioSession` の `.record` カテゴリは**他アプリの再生を完全に中断する**。

```swift
try session.setCategory(.playAndRecord, mode: .measurement,
                        options: [.duckOthers, .defaultToSpeaker])
try session.setActive(true, options: .notifyOthersOnDeactivation)
```

- `.duckOthers`: 音楽は流れ続け、音量だけ下がる。`notifyOthersOnDeactivation` で復帰
- `.defaultToSpeaker` は必須: セッションがアクティブな間は**他アプリの音もこの経路で鳴る**ため、
  外すと音楽が受話口から小さく鳴る事故になる
- Bluetooth イヤホンのマイクを使うなら `.allowBluetoothHFP` の追加を実機で検証すること
