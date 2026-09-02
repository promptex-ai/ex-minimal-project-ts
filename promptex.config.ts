import { claude, defineConfig } from 'promptex-js'

// 兩份擴展是本專案的一部分，以相對路徑直接編譯進來，不走套件解析：Node 的型別
// 剝離不作用於 node_modules 底下的 .ts，擴展若包成套件就得先跑一次建置才裝得動。
import exMinimalAdapter from './adapters/ex-minimal-adapter-ts/src/index.ts'
import { createPlugin } from './plugins/ex-minimal-plugin-ts/src/index.ts'

// 兩個平台目標：claude 是內建適配，ex-minimal-adapter-ts 是本專案自帶的第三方
// 適配，同一份源碼因此投影出兩套平台原生產物。plugin 在求值後的改寫遍追加內容，
// 兩個平台的產物都看得到它的痕跡。
export default defineConfig({
  name: 'ex-minimal-project-ts',
  srcDir: './prompts',
  outDir: '.',
  targets: [claude(), exMinimalAdapter()],
  plugins: [createPlugin()],
})
