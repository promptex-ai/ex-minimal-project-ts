# ex-minimal-adapter-ts

[ex-minimal-project-ts](../../) 的 adapter 擴展。由專案以相對路徑直接編譯進來，不走套件解析：Node 的型別剝離不作用於 node_modules 底下的 .ts，擴展若包成套件就得先跑一次建置才裝得動；同時保持可發布形態——中繼欄位、參數宣告與授權都隨套件出貨，版號比照 promptex 的 alpha 原型套件。

適配以 SDK 層實作，只用 `AdapterContext` 的公開介面。`emit` 的責任鏈固定四步：

1. 算落點表——渲染要靠它解析引用，因此必須在渲染之前完成。
2. 回報不支援的 kind——逐一列進報告，不靜默丟棄。
3. 渲染並產出節點——平台缺某機制時記 degrade 降級。
4. 產出被引用的資源。

本適配示範的平台只有提示詞單檔與參考資料：支援 skill、rule、instruction，不支援 agent、hook、mcp、permission。適配綁語言——同一個平台要服務另兩個生態的專案時，各自以該語言的 SDK 實作一份。

## 在本專案的接法

`promptex.config.ts` 的目標清單寫成 `targets: [claude(), exMinimalAdapter()]`，claude 是內建適配、本擴展是第三方適配，同一份源碼因此投影出兩套平台原生產物。跑 `npx promptex build --install .` 後產物落在 `.ex-minimal-adapter-ts/prompts/`，安裝報告會列出一項降級：範例規則宣告了適用範圍，而本平台無範圍載入機制，改為常駐並在內文標註適用範圍。

## 參數宣告

參數宣告（標準 JSON Schema）住擴展目錄根的 `promptex.config.schema.json`，由 `src/index.ts` 在載入時讀進來（執行期讀檔而非編譯期 JSON import，產物樹因此保持扁平、全包只留套件根那一份），隨中介表示交給讀取端；`promptex config declare ex-minimal-adapter-ts` 讀的是同一份檔案。

## 發布

```bash
npm install
npm pack --dry-run
npm publish --tag alpha --access public
```

`prepack` 綁著 `tsc`，`npm publish` 會自己先建置；`files` 只放 `dist`、參數宣告、README 與 LICENSE。發到 `alpha` 標籤而非 `latest`：預發布版不該被 `npm install` 預設選中，安裝端寫 `npm install ex-minimal-plugin-ts@alpha`。

SDK 依賴不必換：`peerDependencies` 與 `devDependencies` 的 `promptex-js: ^0.0.0` 在 registry 上對到的是 promptex-prototype 發的 `0.0.0` **介面樁**——型別與簽名逐字複製正式版、方法本體一律拋錯。發布驗證（尤其 `cargo publish` 的建置）拿它編得過；裝到消費端也裝得起來，但實際執行要靠工作區覆寫指向本地的正式版 SDK，否則第一個碰到樁的呼叫就會以「promptex 介面樁」開頭的錯誤中止。

名稱刻意不帶 `promptex-adapter-` 前綴——那是給要被消費端搜尋到的套件用的；本擴展的定位是示範，改以 keywords 的 `promptex-adapter` 承載可搜尋性。
