// 第三方 adapter：以 SDK 層實作，只用 AdapterContext 的公開介面。emit 的
// 責任鏈固定四步：① 算落點表 → ② 回報不支援的 kind → ③ 渲染並產出節點
// （平台缺某機制時記 degrade 降級）→ ④ 產出被引用的資源。發布前把落點
// 規則與能力集合換成你的平台實況。
//
// adapter 綁語言：本套件服務 TypeScript 專案；Python／Rust 專案要用同一個
// 平台時，各自以該語言的 SDK 實作一份。
import { readFileSync } from 'node:fs'

import { defineTarget, type AdapterContext, type AdapterTarget, type PluginEntry } from 'promptex-js'

// 參數宣告（標準 JSON Schema）住套件根，由本檔在載入時讀進來。用執行期讀檔而非
// 編譯期 import：JSON 在 include 的 src 之外，靜態 import 會把編譯器的共同來源根
// 抬到套件根，產物因此多一層 src/，包裡還會留下第二份 schema。改讀檔之後
// src/index.ts 與 dist/index.js 對套件根的相對位置相同，兩種形態都指向同一份。
const configSchema = JSON.parse(readFileSync(new URL('../promptex.config.schema.json', import.meta.url), 'utf8'))

/** 建構參數：與 promptex.config.schema.json 的宣告一一對應。 */
export interface Options {
  /** 產物落點的根目錄；預設 `.ex-minimal-adapter-ts`。 */
  readonly root?: string
}

/** 平台能力：本範例只有提示詞單檔與參考資料，無代理、無事件機制。 */
const SUPPORTED = ['skill', 'rule', 'instruction'] as const
const UNSUPPORTED = ['agent', 'hook', 'mcp', 'permission'] as const

export default function target(options: Options = {}): AdapterTarget {
  const root = options.root ?? '.ex-minimal-adapter-ts'
  // 落點規則：提示詞一律單檔平鋪，資源集中於 refs/。
  const nodePath = (e: PluginEntry) => `${root}/prompts/${e.id}.md`
  const resourcePath = (e: PluginEntry) => `${root}/refs/${e.id}.md`

  const emit = (ctx: AdapterContext): Map<string, string> => {
    const files = new Map<string, string>()

    // ① 先算落點表：渲染需要它解析引用，故必須在渲染之前完成。
    const layout = new Map<string, string>()
    for (const kind of SUPPORTED) {
      for (const e of ctx.entries(kind)) layout.set(`${kind}:${e.id}`, nodePath(e))
    }
    for (const kind of ['resource', 'asset', 'dir'] as const) {
      for (const e of ctx.entries(kind)) layout.set(`${kind}:${e.id}`, resourcePath(e))
    }

    // ② 不支援的 kind 逐一列報告，不靜默丟棄。
    for (const kind of UNSUPPORTED) {
      for (const e of ctx.entries(kind)) {
        ctx.unsupported({ kind, nodeId: e.id, feature: kind, note: `ex-minimal-adapter-ts 無 ${kind} 對應機制，該節點未產出` })
      }
    }

    // ③ 產出提示詞單檔；rule 的載入範圍在本平台無對應機制，降級為內文標註。
    for (const kind of SUPPORTED) {
      for (const e of ctx.entries(kind)) {
        const path = nodePath(e)
        const cfg = e.def.config as { appliesTo?: readonly string[] } | undefined
        let note = ''
        if (kind === 'rule' && cfg?.appliesTo?.length) {
          note = `適用範圍：${cfg.appliesTo.join('、')}\n\n`
          ctx.degrade({
            kind,
            nodeId: e.id,
            feature: 'scopedLoading',
            note: 'ex-minimal-adapter-ts 無範圍載入機制，改為常駐並於內文標註適用範圍',
          })
        }
        files.set(path, `${frontmatter(ctx, e)}# ${e.name}\n\n${note}${ctx.render(e, path, layout)}\n`)
      }
    }

    // ④ 被引用的資源。
    for (const e of ctx.entries('resource')) {
      const path = resourcePath(e)
      files.set(path, `# ${e.name}\n\n${ctx.render(e, path, layout)}\n`)
    }

    return files
  }

  // 參數宣告隨中介表示交給讀取端；
  // `promptex config declare` 讀的是套件根的同一份檔案。
  return defineTarget('ex-minimal-adapter-ts', emit, { configSchema })
}

// 平台原生鍵的覆寫：一律經 ctx.overrides 讀取，不自己走
// entry.def.config.platforms：「空物件視同未宣告」的判定與框架保留鍵
// （promptex: 前綴）的過濾都由核心同一份實作承載，自己讀會各自重造而漂移。
const frontmatter = (ctx: AdapterContext, e: PluginEntry): string => {
  const overrides = ctx.overrides(e)
  if (!overrides) return ''
  return `---\n${Object.entries(overrides).map(([k, v]) => `${k}: ${String(v)}`).join('\n')}\n---\n\n`
}
