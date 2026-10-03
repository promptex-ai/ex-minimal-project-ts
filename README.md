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

兩份擴展是本專案的一部分：它們不自成工作區、不帶各自的消費專案、名稱也不加 registry 搜尋用的 `promptex-plugin-`／`promptex-adapter-` 前綴（改以 keywords 承載可搜尋性）。兩者同時保持可發布形態，中繼欄位齊備、版號是 1.0.0 正式版，發布流程見「發布」一節。`promptex.config.ts` 以相對路徑直接 import 兩份擴展的源碼，不走套件解析：Node 的型別剝離不作用於 `node_modules` 底下的 `.ts`，擴展若包成套件就得先跑一次建置才裝得動。

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

## 發布

兩份擴展各自發布到 npm（`ex-minimal-plugin-ts`、`ex-minimal-adapter-ts`），以 release-please 的 linked-versions 綁成同一個版號。根目錄的專案是 `private`，不發布。流程是 main 線開發加短命的發布分支 `release/v<X.Y>`：版號只在發布分支上計算，main 不帶版號 commit。

| 檔案 | 作用 |
| :--- | :--- |
| `release-please-config.json`、`.release-please-manifest.json` | 兩個單元的 release-type（node）、共享版號群組與目前版號 |
| `scripts/release/cut-release.sh` | 切發布分支，把設定縮到本班單元，選起始階段 |
| `scripts/release/advance-release.sh` | 把發布分支推進到後面的階段（alpha → beta → rc → ga） |
| `scripts/release/finalize-release.sh` | GA、合回 main、關閉三階段 |
| `scripts/release/publish-units.sh` | 被 `publish.yml` 呼叫，逐單元核對版號與階段後發布 |
| `.github/workflows/release-please.yml` | 在發布分支上開 Release PR、建單元 tag，再派送 `publish.yml` |
| `.github/workflows/publish.yml` | 以 Trusted Publishing 發布到 npm，只接受 `workflow_dispatch` |
| `.github/workflows/release-line-finalize.yml` | 產品 tag `vX.Y.Z` 推上後建立產品 GitHub Release |

腳本需要 bash 4 以上、git、jq，以及已登入的 gh。macOS 內建的 `/bin/bash` 是 3.2，先 `brew install bash`。`cut-release.sh`、`advance-release.sh`、`finalize-release.sh` 都接受 `--dry-run`：只印出會做的事，不建分支、不 commit、不推送。對外寫入（推送、開 PR、合併、打 tag）執行前會逐項詢問，加 `--yes` 才略過詢問。

npm 端兩個套件都要登記 Trusted Publisher：owner `promptex-ai`、repo `ex-minimal-project-ts`、workflow `publish.yml`、environment 留空。`publish.yml` 不使用任何 token，發布時帶 provenance。

### 發布 1.0.0

兩個單元還沒有單元 tag，所以 `cut-release.sh` 把它們當首次發布：起始版號取 `--line` 的 `<X.Y>.0`，並各補一個帶 `Release-As` 的 commit 釘住版號。`--stage ga` 讓第一個 Release PR 就是正式版。

1. 試跑，確認輸出列出兩個單元的 `Release-As 1.0.0` 與 `linked-versions`：

   ```bash
   bash scripts/release/cut-release.sh --line 1.0 --units ex-minimal-plugin-ts,ex-minimal-adapter-ts --stage ga --dry-run
   ```

2. 拿掉 `--dry-run` 再跑一次。腳本在本機切出 `release/v1.0`、提交縮小後的設定與兩個 `Release-As` commit，確認後推送分支。
3. `release-please.yml` 在 `release/v1.0` 上開 Release PR，內容是兩個套件的 CHANGELOG 與 manifest 的 1.0.0。合併它。
4. `release-please.yml` 再跑一次，建立 `ex-minimal-plugin-ts/v1.0.0` 與 `ex-minimal-adapter-ts/v1.0.0` 兩個 tag，並派送 `publish.yml` 把兩個套件以 dist-tag `latest` 發布到 npm。
5. 在 `release/v1.0` 上合回 main。腳本推送 `release/v1.0--to-main` 並開 PR：

   ```bash
   bash scripts/release/finalize-release.sh --line 1.0 --phase merge-back --product-version 1.0.0
   ```

6. 確認 PR 內容後收尾。腳本以 squash 合併 PR、在發布分支的最後一個 commit 打產品 tag `v1.0.0`、刪除發布分支，推上的 tag 觸發 `release-line-finalize.yml`：

   ```bash
   bash scripts/release/finalize-release.sh --line 1.0 --phase close --product-version 1.0.0
   ```

### 之後的發布

之後的版號全由 release-please 依 commit 計算。不帶 `--stage` 時從 alpha 開始，每個預發布階段都發布到 npm，dist-tag 是階段名。每個階段都先合併該階段的 Release PR、等 `publish.yml` 發布完，再推進到下一個階段：

```bash
bash scripts/release/cut-release.sh --line 1.1 --units ex-minimal-plugin-ts,ex-minimal-adapter-ts
bash scripts/release/advance-release.sh --line 1.1 --to beta
bash scripts/release/advance-release.sh --line 1.1 --to ga --product-version 1.1.0
```

推進到 ga 後，照「發布 1.0.0」的第 5、6 步合回 main 並收尾。產品線已有 `vX.Y.Z` 時，修補發布要從最後一個產品 tag 切：`cut-release.sh --line 1.0 --units ... --from v1.0.0`。
