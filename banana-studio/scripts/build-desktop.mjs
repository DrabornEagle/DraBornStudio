import { build } from 'esbuild';
import path from 'node:path';
import fs from 'node:fs';
const root=path.resolve(import.meta.dirname,'..');
const replacements={auth:'auth.mjs',openaiGuard:'guard.mjs',imageJobQueue:'queue.mjs',providerMedia:'providerMedia.mjs',rasterCodec:'rasterCodec.mjs'};
fs.mkdirSync(path.join(root,'.build/desktop'),{recursive:true});
const result=await build({entryPoints:[path.join(root,'desktop/server/main.mjs')],outfile:path.join(root,'.build/desktop/server.mjs'),platform:'node',target:'node24',format:'esm',banner:{js: "import { createRequire as __bananaCreateRequire } from 'node:module'; const require = __bananaCreateRequire(import.meta.url);"},bundle:true,packages:'bundle',external:['sharp'],sourcemap:false,metafile:true,plugins:[{name:'local-workspace-boundary',setup(build){build.onResolve({filter:/(auth|openaiGuard|imageJobQueue|providerMedia|rasterCodec)\.(js|ts)$/},args=>{
 const resolved=path.resolve(args.resolveDir,args.path);if(path.dirname(resolved)!==path.join(root,'api/_lib'))return;
 const name=path.basename(args.path).replace(/\.(js|ts)$/,'');return {path:path.join(root,'desktop/server',replacements[name])};
});}}]});
fs.writeFileSync(path.join(root,'.build/desktop/metafile.json'),JSON.stringify(result.metafile));
console.log('Built the standalone workspace server.');
// An ICO directory can contain a PNG unchanged. Reuse the existing app artwork
// so the Windows taskbar/window and Mac Dock identify the same application.
const png=fs.readFileSync(path.join(root,'public/icon-192.png'));
const ico=Buffer.alloc(22);ico.writeUInt16LE(1,2);ico.writeUInt16LE(1,4);
ico[6]=192;ico[7]=192;ico.writeUInt16LE(1,10);ico.writeUInt16LE(32,12);ico.writeUInt32LE(png.length,14);ico.writeUInt32LE(22,18);
fs.writeFileSync(path.join(root,'.build/BananaStudio.ico'),Buffer.concat([ico,png]));
