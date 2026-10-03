# ex-minimal-project-ts

promptex 的最小 TypeScript 消費端專案，同時是 [promptex-resources-ts](https://github.com/promptex-ai/promptex-resources-ts) 的 `example/` 成員（以 submodule 掛入）。骨架由 `promptex init` 產出，之上接了兩份擴展，讓「一份源碼投影到多個平台」與「擴展如何介入」都成為可讀的既成事實。

## 結構

| 內容 | 作用 |
| :--- | :--- |
| `package.json` | 套件宣告檔，宣告對 SDK 的依賴（兩份擴展不走套件解析，不出現在這裡） |
| `promptex.config.ts` | 配置檔，宣告單元名、源碼目錄、產物落點、目標平台與 plugin |
| `prompts/example.ts` | 提示詞源碼。一份最小的規則宣告，帶適用範圍 |
| `plugins/ex-minimal-plugin-ts/` | plugin 擴展，在改寫遍為每個 skill 與 rule 追加一行 |
| `adapters/ex-minimal-adapter-ts/` | 第三方平台適配擴展，把同一份源碼投影成另一套平台原生產物 |

兩份擴展是本專案的一部分：它們不自成工作區、不帶各自的消費專案、名稱也不加 registry 搜尋用的 `promptex-plugin-`／`promptex-adapter-` 前綴（改以 keywords 承載可搜尋性）。兩者同時保持可發布形態，中繼欄位齊備、版號是 1.0.0 正式版，發布指令見各自的 README。`promptex.config.ts` 以相對路徑直接 import 兩份擴展的源碼，不走套件解析：Node 的型別剝離不作用於 `node_modules` 底下的 `.ts`，擴展若包成套件就得先跑一次建置才裝得動。

## 建置與產物

```bash
pnpm install
npx promptex build --install .
```

產物落在專案根（配置單元的 `out_dir` 是 `.`），並隨源碼一起入版控——讀者不必先跑指令就看得到源碼與產物的對應：

- `.claude/rules/example-rule.md`——內建 claude 適配的產物，frontmatter 帶 `paths` 載入宣告
- `.ex-minimal-adapter-ts/prompts/example-rule.md`——第三方適配的產物
- `.promptex/ex-minimal-project-ts/claude.json` 與 `.promptex/ex-minimal-project-ts/ex-minimal-adapter-ts.json`——兩個平台各自的所有權登記，下一次安裝據它 prune

`npx promptex build .` 只刷新框架中繼，不落平台產物。

## 讀產物時看什麼

- 兩份產物出自同一份源碼，差別全在適配：落點、檔案格式與載入宣告的表達方式由平台決定，源碼裡沒有任何平台相關程式碼
- 兩份產物的內文末尾都多出一行「本節點由 ex-minimal-plugin-ts plugin 追加此行」，那是 plugin 在改寫遍介入的可見證據
- 範例規則宣告了適用範圍，屬載入宣告三態中的範圍載入態：claude 產物把它表達成 frontmatter 的 `paths`；第三方適配無範圍載入機制，安裝報告因此記一項降級，改為常駐並在內文標註適用範圍
- 中繼與登記落在 `.promptex/ex-minimal-project-ts/` 而非推導出的 `unit-0`，因為配置宣告了單元名；未宣告時名字綁在陣列位置上，日後在前面插入第二個單元即等同把第一個單元改名

## 與 init 骨架的差異

骨架的產物原樣保留，只做以下調整：

| 項目 | 骨架 | 本專案 | 差異理由 |
| :--- | :--- | :--- | :--- |
| 套件名與配置單元名 | `promptex-prompts` | `ex-minimal-project-ts` | 本專案要當 promptex-resources-ts 的工作區成員，成員名必須唯一，且本倉庫的慣例是成員名等於目錄名 |
| 目標平台與 plugin | 只有 claude | 加上第三方適配與 plugin | 骨架示範的是最小可建置形態；本專案要示範的是擴展怎麼介入，兩份擴展因此接進配置 |
