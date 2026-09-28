---
name: canvas-dom-hybrid-ui
description: >
  Canvas ゲームエンジン (Phaser 等) の UI を React/DOM オーバーレイに移行・共存させる
  ときの設計契約とハマりどころ。メニューやダイアログの文字はみ出しを CSS に任せたい
  ケース、キー入力がエンジン側と DOM 側の両方に届く構成で使う。
---

# Canvas + DOM 混成UI (Phaser × React など)

## いつ使うか

- Canvas 手描きのメニュー/ダイアログが「文字はみ出し・手動レイアウト地獄」になった
- ゲーム世界は Canvas、UI は DOM に分けたい (折り返し・スクロール・タップ領域を CSS に任せる)

## 設計契約 (実績パターン)

1. **シーン側 API は変えない**。エンジン側に薄いブリッジ (例: UiScene) を残し、
   `showMessage(pages, onDone)` 等の同期APIと busy 管理だけを担わせる。
   描画は React が `"ui-message" {id, ...}` を受けて行い、完了を
   `"ui-message-done" {id}` で返す。**id 照合**で古い完了イベントを無視する。
2. **busy は発行側で同期管理** (`activeIds` セット)。emit した瞬間に busy=true に
   なるので、E2E や移動ロックが「表示前の隙間」を踏まない。
3. **タップ完結を第一に** (iPad 等)。キーボードは補助。DOM オーバーレイは
   全画面バックドロップでタップを吸収し、Canvas への誤伝播を防ぐ。

## ハマりどころ (実体験)

### 1. 同一キーイベントが「開いて即閉じる」

エンジンのリスナーがパネルを開く → **リスナー間で microtask checkpoint が走り
React が再レンダー** → 同じ keydown が後続の React リスナーに届き、
「開いている→閉じる」判定で即 close される。

対策: リクエストを開いた時刻を記録し、**それ以前に発火したイベントを無視**する。

```ts
openedAtRef.current = performance.now();   // 開いたとき
if (e.timeStamp <= openedAtRef.current) return;  // キーハンドラ冒頭
```

### 2. クールダウンをフレーム時間で測らない

`scene.time.now` はタブ非表示・高負荷でフレームが止まると進まない。
「実時間で 400ms 待ったのにクールダウンが明けず入力が飲み込まれる」が起きる
(E2E で顕在化)。**壁時計 (`performance.now()`) で判定する**。

### 3. 隠れタブでゲームループは完全停止する

`document.visibilityState === "hidden"` だと rAF が 0fps になり、tween /
時間経過依存の処理が全部止まる。ブラウザ自動化での「フリーズ再現」は
まずタブの可視性を疑う (`framesIn1s` を rAF で数えると即断できる)。

### 4. E2E の失敗判定

並行ビルド等で機械が飽和していると、フルスイートでは環境起因の失敗が出る
(初期描画 30 秒超え等)。**失敗テストは単体で再実行して判定**する。
実バグ調査は一時 spec で内部状態 (busy / runActive / 時刻) を JSON ダンプすると速い。

### 5. DOM 窓のポップ演出は `scale` / `translate` 個別プロパティで

canvas の上に出す窓は `left: 50%; transform: translateX(-50%)` で中央寄せしがち。
開くアニメを `transform: scale()` で書くと中央寄せが上書きされて一瞬ずれる。
**CSS の個別プロパティ `scale` / `translate` を keyframes に使う**と既存の
`transform` と合成され壊れない (ボタンの押下沈み込み `button:active { translate: 0 2px }` も同様)。
`prefers-reduced-motion` で `animation-duration: 0.01ms !important` の全体停止を併設する。

### 6. ポップ演出を入れたら「大きさを測る E2E」が落ちる

`boundingBox()` で タップ領域 ≥56px などを検証していると、開き途中 (scale 0.96) を
測って 53.8px で落ちる。測る前に
`await el.evaluate(e => Promise.all(e.getAnimations({ subtree: true }).map(a => a.finished)))`
で アニメ完了を待つ (固定 sleep は使わない)。

### 7. canvas の上の `backdrop-filter` は重い

背後の canvas が毎フレーム描き変わると blur も毎フレーム再計算になる。
戦闘中など頻繁に出る窓は 半透明の暗幕だけにし、blur は静的な場面 (プロフィール選択等) に限る。
