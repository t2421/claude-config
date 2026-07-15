---
name: paperproto-api
description: >-
  自作iOSアプリ「PaperProto」(ペーパープロトタイピングツール) をAPI経由で操作し、
  アプリのUI/UXプロトタイプを高速に作る手順書。「プロトタイプを作って」「ワイヤーフレームで
  導線を検証したい」「PaperProtoに流し込んで」「画面フローのモックを実機で見たい」等、
  アプリのアイディア・画面フロー・UX導線を検証したい場面で使う。JSONを書いてPUTするだけで
  実機/シミュレータに動くプロトタイプが現れ、PNGで自己検証でき、被験者の操作ログも取れる。
origin: user
---

# PaperProto API — AIによるプロトタイプ作成

PaperProto はプロトタイプを**宣言的JSON**で表現するiOSアプリ。AIはHTTP APIでJSONを
流し込むだけで、タブ・画面遷移・フォーム・カメラ風UIなどが動くワイヤーフレームを作れる。
見た目はモノクロ固定(スタイル指定は存在しない)なので、構造と導線だけに集中できる。

- 本体リポジトリ: `~/projects/t2421/prototyping` (private: t2421/paperproto)。スキーマ詳細は同リポジトリの README / CLAUDE.md
- **サーバーはアプリ内で動く** (別プロセスなし)。アプリが起動していなければAPIは応答しない

## 1. 接続先の確立 (3経路、上から試す)

### a. シミュレータ (開発ループに最適)

```bash
xcrun simctl launch --terminate-running-process booted com.t2421.paperproto -bridge
# サーバー起動を待つ (アプリ起動直後は未応答)
for i in $(seq 1 20); do curl -s -m 1 -o /dev/null http://localhost:8787/prototypes && break; sleep 0.5; done
```

アプリ未インストールなら本体リポジトリで `./bootstrap.sh` → ビルド → `simctl install`。

### b. 実機 (ユーザーの体感確認用)

ユーザーがアプリの「AI Bridge」トグルをオンにしている必要がある。同一Wi-FiのMacから
`http://<デバイスのホスト名>.local:8787` (例: t2421.local)。届かなければユーザーに
「Bridgeをオンにして」と依頼する。

### c. Google Drive (端末に今すぐ届かないとき)

Drive の「PaperProto」フォルダに `<名前>.json` を置く (Claude の Drive 連携ツールで書ける)
→ ユーザーがアプリで「Google Driveから同期」をタップすると `gdrive-<名前>` として取り込まれる。
push (Bridge) と pull (Drive) の使い分け: リアルタイムに直したいなら Bridge、
時間差で届けばよいなら Drive。

## 2. 黄金ワークフロー

```bash
curl -s $BASE/schema            # 1. 全29ブロックのプロパティ仕様+実例JSON (必ず最初に読む)
curl -s -X PUT $BASE/prototypes/<id> --data-binary @doc.json   # 2. 流し込み
#    → 応答の warnings (未知ブロック・宙に浮いた遷移・到達不能画面・空画面) が
#      空になるまで修正する。「warnings空 = 構造として完全」が終了条件
curl -s -o s.png $BASE/prototypes/<id>/screens/<screenID>.png  # 3. 見た目をPNGで自己検証
#    → Readツールで画像を見て、レイアウト破綻・違和感を自分で直す
```

- id は英数と `-` `_` のみ (それ以外は400)
- **プレイ中のプロトタイプにPUTすると約2秒でライブリロード**される。ユーザーが実機で
  触りながら「ここ直して」→ PUT → 即反映、が最強のループ
- lint は構造検証のみ。**見た目の妥当性はPNGで必ず別途確認**する (rules にも明記されている)

## 3. スキーマ最小例 (詳細は GET /schema が正典)

```json
{
  "title": "デモ", "start": "home",
  "tabBar": { "items": [ { "icon": "house", "label": "ホーム", "screen": "home" } ] },
  "tasks": [ { "title": "購入まで進める", "goal": "done" } ],
  "screens": [
    { "id": "home",
      "nav": { "title": "ホーム", "trailing": { "icon": "plus", "action": "sheet:add" } },
      "children": [
        { "type": "searchBar", "placeholder": "探す" },
        { "type": "grid", "columns": 2, "repeat": 6, "action": "push:done",
          "item": { "type": "card", "title": "{{title}}" } }
      ] },
    { "id": "add", "children": [ { "type": "textField", "placeholder": "名前" } ] },
    { "id": "done", "children": [ { "type": "text", "text": "完了", "role": "title" } ] }
  ]
}
```

- アクション: `push:<id>` `sheet:<id>` `back` `dismiss` `tab:<n>` `alert:<msg>|<btns>` `actionSheet:<opts>` `toast:<msg>`
- ダミートークン: `{{name}} {{title}} {{caption}} {{price}} {{index}}` (repeat内でindexごとに変わる)
- `tasks` を定義すると Play 開始時に被験者へお題が提示され、ゴール画面到達で自動計測される

## 4. UX検証結果の分析

```bash
curl -s $BASE/sessions/<id>    # プレイ操作ログ (JSON配列)
```

- `events`: アクションに加え `view:<画面>` (画面表示トレース)、`task-start/complete`、
  `system:` (Player UI操作) が自動記録される。`view:` を辿ると迷走経路がわかる
- `taps`: 生タップ座標。**直後にイベントが無いタップ = 無反応タップ = 導線が伝わっていないシグナル**
- タスク達成率・所要時間はアプリのInspectorでも見られる。「どこで迷ったか分析して直す」までAIで完結できる

## 5. ハマりどころ

| 症状 | 原因と対処 |
|---|---|
| 接続できない (000) | アプリが起動していない/Bridge未起動。simctl launch -bridge、実機ならトグル確認。起動直後は readiness ループで待つ |
| warnings「到達できません」 | alert のボタンは遷移しない仕様。完了画面へは push で繋ぐ |
| PNGでカルーセル等が横に見切れる | スナップショットは非スクロール描画 (先頭側のみ)。実機Playでは正常にスクロールする |
| PUTが400 | id に日本語や記号。英数 `-_` のみに |
| Driveに置いたのに出てこない | 同期は手動 (ユーザーが「同期」をタップ)。自動ではない |
| デモを直接開きたい | 起動引数 `-autoplay <id>` でPlayerを直接開ける (スクショ検証に便利) |
