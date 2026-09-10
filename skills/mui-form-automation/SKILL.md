---
name: mui-form-automation
description: >
  MUI (Material UI) 製の Web フォームを Chrome 拡張の javascript_tool から一括入力する手順。
  MUI Select が form_input で動かない、Autocomplete に自由入力したい、チップ選択式の
  ピッカーを開いて選びたい、React 管理の input/textarea に値を入れても反映されない、
  という状況で使う。求人サイト・SaaS の設定画面などを職歴データから埋めるときに有効。
---

# MUI フォームを JS で埋める

## いつ使うか

- `read_page` で `combobox` と出るが `<select>` ではなく `div[role=combobox]` (MUI Select)
- `form_input` で値を入れても保存ボタンが有効にならない (React state に届いていない)
- 1画面に何十項目もあり、1クリックずつ操作すると往復が多すぎる

## 核心 3 点

1. **React 管理の input/textarea** は native setter → `input` イベントで入れる
2. **MUI Select** は `mousedown` で開く (click では開かない)。listbox は
   `aria-controls` の id で引く (複数開いていても取り違えない)。option は `data-value` で特定し `.click()`
3. **Autocomplete の自由入力**は値を入れると「「X」として登録する」候補が出るが、
   そのまま次へ進めば値は保持される (候補クリック不要)

## 雛形

```js
const sleep = ms => new Promise(r => setTimeout(r, ms));

// 1. React input/textarea
window.__set = (el, value) => {
  const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
  return el.value;
};

// 2. MUI Select: root 内の idx 番目の combobox に data-value=value を選ぶ
window.__pickIn = async (root, idx, value) => {
  const cb = [...root.querySelectorAll('div[role=combobox]')][idx];
  cb.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0 }));
  await sleep(300);
  const lb = document.getElementById(cb.getAttribute('aria-controls'));
  const opt = lb && lb.querySelector(`[role=option][data-value="${value}"]`);
  if (!opt) { document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })); return { err: 'no option' }; }
  opt.click(); await sleep(300);
  return cb.textContent;
};

// 3. チップ選択式ピッカー (Menu 内に ListItemButton のカテゴリ + Chip の候補)
window.__pickChip = async (root, label, category) => {
  const cb = [...root.querySelectorAll('div[role=combobox]')][0];
  cb.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0 })); await sleep(500);
  const pop = document.querySelector('.MuiMenu-root');
  let chip = [...pop.querySelectorAll('.MuiChip-root')].find(c => c.textContent.trim() === label);
  if (!chip && category) {
    [...pop.querySelectorAll('.MuiListItemButton-root')].find(e => e.textContent.trim() === category).click();
    await sleep(500);
    chip = [...pop.querySelectorAll('.MuiChip-root')].find(c => c.textContent.trim() === label);
  }
  chip.click(); await sleep(400);
  return cb.textContent;
};
```

モーダル (`[role=dialog]`) を root に渡すと、背後のページと取り違えない。
ステップ式モーダルは「次へ」クリック後に `document.querySelector('[role=dialog]')` を**取り直す**。
保存は `button` を `textContent` で探して `.disabled` を確認してから `.click()`。

## 手順

1. `read_page filter=interactive` で combobox の数と順序を把握する
2. `__pickIn(root, idx)` を value 無しで呼び、option の `data-value` 一覧を取得 (雇用形態などの enum 値はここで判明)
3. 1件を手で通して保存成功トーストを確認してから、残りをループで流す
4. 最後に `get_page_text` で登録内容を読み直して検証する

## ハマりどころ

- `document.querySelector('[role=listbox]')` は複数ポップアップが開いていると別の listbox を掴む
  → 必ず `aria-controls` で引く。掴み損ねると Select が開きっぱなしで重なる (Escape 連打で回復)
- Python の `re.sub` で JS/Python 文字列を書き換えるとき、置換文字列の `\n` は実改行に展開される
  → `lambda m: text` で渡す
- textarea には `maxlength` がある (例: 300字)。超えると入力が黙って切れるので、
  投入前に `text.length` を検証する

## 補遺: Vue (v-model) のフォームと、長い JS 実行のハマりどころ

- **Vue 2 の v-model** は React より素直。`el.value = v` の後に `input` と `change` を
  dispatch すれば反映される（input 要素に `_value` プロパティがあれば Vue 管理）。
  radio / checkbox は `.click()`。`<input type=month>` は `"2022-04"` 形式で入る
- **SPA なら `window.__helper` は画面遷移後も生きる**。`a.click()` で遷移 → フォーム出現を
  ポーリング → 入力 → 保存 → 一覧に戻るのを1回の JS 呼び出しで回せる
- **`javascript_tool` は 45 秒でタイムアウトするが、ページ側の JS は止まらず完走する**。
  タイムアウト後は「再実行」せず、まず状態を読み直して差分だけ続きを流す
  （再実行すると二重追加・二重クリックになる）。1 呼び出しは 10〜20 操作程度に分割する
- react-select の行ごとの年数ドロップダウンは、`input` に focus → `ArrowDown` の keydown で
  開き、`aria-controls` の listbox から option を `.click()`。検索型 Autocomplete の
  候補が無い語（マスタ未登録）を続けて投げると固まりやすいので、1語ずつ確認する
