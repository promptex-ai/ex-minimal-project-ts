import { claude, defineConfig } from 'promptex-js'

export default defineConfig({
  name: 'ex-minimal-project-ts',
  srcDir: './prompts',
  outDir: '.',
  targets: [claude()],
})
