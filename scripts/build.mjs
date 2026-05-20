import { builtinModules } from 'node:module';
import { resolve } from 'node:path';
import react from '@vitejs/plugin-react';
import { build } from 'vite';

const root = process.cwd();
const external = ['electron', ...builtinModules, ...builtinModules.map((name) => `node:${name}`)];

await build({
  configFile: false,
  build: {
    ssr: resolve(root, 'src/main/index.ts'),
    outDir: resolve(root, 'out/main'),
    emptyOutDir: true,
    rollupOptions: {
      external,
      output: {
        format: 'es',
        entryFileNames: 'index.js'
      }
    }
  }
});

await build({
  configFile: false,
  build: {
    lib: {
      entry: resolve(root, 'src/preload/index.ts'),
      formats: ['es'],
      fileName: () => 'index.mjs'
    },
    outDir: resolve(root, 'out/preload'),
    emptyOutDir: true,
    rollupOptions: {
      external: ['electron']
    }
  }
});

await build({
  configFile: false,
  root: resolve(root, 'src/renderer'),
  plugins: [react()],
  build: {
    outDir: resolve(root, 'out/renderer'),
    emptyOutDir: true,
    rollupOptions: {
      input: resolve(root, 'src/renderer/index.html')
    }
  }
});
