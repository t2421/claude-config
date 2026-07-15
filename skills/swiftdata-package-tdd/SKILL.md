---
name: swiftdata-package-tdd
description: >-
  SwiftData を使う iOS アプリのドメインロジックを SwiftPM パッケージに切り出し、
  シミュレータ不要の `swift test` (macOS ネイティブ実行、数秒) で高速TDDする構成パターン。
  「SwiftDataのテストが遅い」「xcodebuild testを待ちたくない」「iOSアプリをTDDで作りたい」
  「オフライン同期 (Outbox) を設計したい」場面で使う。
origin: user
---

# SwiftData ドメインを SwiftPM パッケージで高速TDDする

## 核心

SwiftData は macOS 14+ でも動く。ドメインロジック (モデル+サービス) をアプリターゲットから
SwiftPM パッケージに分離すれば、**シミュレータ起動なしの `swift test` が数秒で回る**。
xcodebuild test (数分) との差は TDD の成立可否に直結する。

```
ios/
├── project.yml            # XcodeGen。アプリターゲットは packages: で BerryCore を参照
├── AppName/               # SwiftUI ビュー層のみ (薄く保つ)
└── CoreName/              # ← ここを swift test で回す
    ├── Package.swift      # platforms: [.iOS(.v17), .macOS(.v14)] が肝
    ├── Sources/CoreName/  # @Model + サービス + APIクライアント
    └── Tests/CoreNameTests/
```

```swift
// Package.swift — swift-tools-version 5.10 にすると Swift 6 strict concurrency を避けられる
let package = Package(
    name: "CoreName",
    platforms: [.iOS(.v17), .macOS(.v14)],   // macOS を入れないと swift test できない
    products: [.library(name: "CoreName", targets: ["CoreName"])],
    targets: [
        .target(name: "CoreName"),
        .testTarget(name: "CoreNameTests", dependencies: ["CoreName"])
    ]
)
```

## テストの定型

```swift
enum TestSupport {
    static func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Customer.self, Sale.self,   // 全 @Model を列挙
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
    /// "yyyy-MM-dd" をローカル正午として解釈 (日付境界のブレ防止)
    static func date(_ s: String) -> Date { /* DateComponents で hour=12 */ }
}
```

- テストごとに `ModelContext(container)` を作る。同一 context 内なら未saveの insert も fetch に見える
- `@Attribute(.unique)` は避ける (in-memory との相性・upsert暗黙動作の罠)。一意性はサービス層で守る

## ハマりどころ

| 症状 | 対処 |
|---|---|
| ソート指定なし fetch の順序を assert して flaky | 順序保証が要るなら `seq: Int` を自前で持ち `SortDescriptor(\.seq)`。挿入順に依存しない |
| 非隔離 `async` サービスから `container.mainContext` を触ってデータ競合 | ModelContext を扱う async サービスは `@MainActor` に隔離するか `@ModelActor` を使う。Swift 5 モードはこれを**検出しない**ので設計で守る |
| Outbox (オフライン送信キュー) がプロセス kill で消える | enqueue 直後に `try context.save()` (write-ahead)。autosave はネットワーク送信より先に走る保証がない |
| 相対パスで保存したファイルが再起動後に見つからない | iOS はコンテナ絶対パスが起動ごとに変わる。**ファイル名のみ永続化**し、基準ディレクトリと合成する |

## Outbox 同期の設計メモ (併用推奨)

- ID は**クライアント生成 UUID + サーバー側冪等 upsert** → 再送が安全になる
- 失敗は2分類: 一時 (通信断/5xx/401/408/429) = キューに残して throw、
  恒久 (その他4xx/payload破損/画像消失) = dead-letter として除去し後続を止めない
- 再送契機は「scene active」だけでは不足。`NWPathMonitor` の復旧通知も足す
