// Loads the shipped Edge Function TypeScript under Node by transpiling each
// module with the repository's own TypeScript package. Imports between shared
// modules are resolved recursively, so tests execute the real source instead of
// a copy. Supabase/Deno type-only imports are erased by the compiler.
import { readFileSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const ts = require('typescript');

function resolveLocal(fromDir, specifier) {
  const base = resolve(fromDir, specifier);
  const candidates = [
    base,
    `${base}.ts`,
    `${base}.tsx`,
    resolve(base, 'index.ts'),
  ];
  for (const candidate of candidates) {
    if (existsSync(candidate) && candidate.endsWith('.ts')) return candidate;
  }
  throw new Error(`Could not resolve ${specifier} from ${fromDir}`);
}

export function loadTsModule(entryPath) {
  const cache = new Map();

  function load(path) {
    if (cache.has(path)) return cache.get(path).exports;
    const source = readFileSync(path, 'utf8');
    const compiled = ts.transpileModule(source, {
      compilerOptions: {
        module: ts.ModuleKind.CommonJS,
        target: ts.ScriptTarget.ES2022,
        esModuleInterop: true,
      },
      fileName: path,
    }).outputText;

    const module = { exports: {} };
    cache.set(path, module);
    const dir = dirname(path);

    const localRequire = (specifier) => {
      if (specifier.startsWith('.')) return load(resolveLocal(dir, specifier));
      return require(specifier);
    };

    // eslint-disable-next-line no-new-func
    const factory = new Function('exports', 'require', 'module', '__filename', '__dirname', compiled);
    factory(module.exports, localRequire, module, path, dir);
    return module.exports;
  }

  return load(resolve(entryPath));
}
