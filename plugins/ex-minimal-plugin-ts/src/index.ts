// 最小可發布 plugin：三個生命週期各示範一件事，發布前把內容換成你的邏輯。
// 生命週期固定順序：prepare（唯一 async 的階段，收集遍之前）→ 源碼求值 →
// transform（改寫遍）→ validate（解析遍，核心檢查在先）。
import configSchema from '../promptex.config.schema.json' with { type: 'json' }
import type { Diagnostic, Plugin } from 'promptex-js'

/** 建構參數：與 promptex.config.schema.json 的宣告一一對應。 */
export interface Options {
  /** transform 階段追加到每個 skill 與 rule 的內容；省略時用預設文字。 */
  readonly banner?: string
}

const DEFAULT_BANNER = '（本節點由 ex-minimal-plugin-ts plugin 追加此行）'

export function createPlugin(options: Options = {}): Plugin {
  // prepare 取得的資料存進閉包，transform 只讀閉包、不知道資料從何而來。
  let banner = ''

  return {
    name: 'ex-minimal-plugin-ts',
    // 宣告本擴充作用在哪幾種節點類型（供文件與讀取端），不隱含過濾。
    kinds: ['skill', 'rule'],
    // 相容的框架版本範圍：安裝的 promptex-js 落在範圍外時於編譯開始前報錯。
    version: '^0.0.0',
    // 參數宣告（標準 JSON Schema）：由本檔自己 import、隨中介表示交給讀取端；
    // `promptex config declare` 讀的是套件根的同一份檔案。
    configSchema,

    // 準備：唯一 async 的生命週期。真實 plugin 在這裡請求外部資源，或以
    // ctx.cacheDir 快取、ctx.writeLock 記錄鎖定；本範例只把參數收斂成
    // transform 要用的值。
    async prepare() {
      banner = options.banner ?? DEFAULT_BANNER
    },

    // 改寫：改寫既有節點一律經 ctx 操作函式（appendContent／patchConfig），
    // 型別安全、變更可追蹤、衝突可偵測；也可在此以 define* 新增節點。
    transform(ctx) {
      for (const entry of ctx.entries) {
        if (entry.kind === 'skill' || entry.kind === 'rule') ctx.appendContent(entry, banner)
      }
    },

    // 驗證：對註冊表做結構驗證，回傳診斷（空陣列即通過）。
    validate(ctx): Diagnostic[] {
      return ctx.entries
        .filter((e) => e.id.startsWith('promptex-'))
        .map((e) => ({
          code: 'ex-minimal-plugin-ts-reserved-id',
          message: `節點 ${e.id} 以保留前綴 promptex- 命名，請改用其他 id`,
          at: [e.at],
          severity: 'error',
        }))
    },
  }
}
