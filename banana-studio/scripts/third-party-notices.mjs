import fs from 'node:fs';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'..');
const meta=JSON.parse(fs.readFileSync(path.join(root,'.build/desktop/metafile.json')));
const sources=Object.values(meta.outputs).flatMap(output=>Object.entries(output.inputs).filter(([,value])=>value.bytesInOutput>0).map(([name])=>name));
sources.push(...JSON.parse(fs.readFileSync(path.join(root,'.build/web-modules.json'))));
const packages=new Map();
for(const source of sources){
 if(!source.includes('node_modules/'))continue;
 let directory=path.dirname(path.resolve(root,source.replace(/^\0/,'')));
 while(directory.startsWith(path.join(root,'node_modules'))){
  const file=path.join(directory,'package.json');
  if(fs.existsSync(file)){const pkg=JSON.parse(fs.readFileSync(file));if(pkg.name&&pkg.version){packages.set(pkg.name+'@'+pkg.version,{...pkg,directory});break;}}
  directory=path.dirname(directory);
 }
}
const sections=['# Third-party notices\n\nBanana Studio source is MIT licensed. Bundled dependencies retain their own licenses. This inventory is generated from modules actually included in the web and macOS builds, rather than unbundled development or server packages.\n'];
for(const [name,pkg] of [...packages].sort(([a],[b])=>a.localeCompare(b))){
 const names=fs.readdirSync(pkg.directory).filter(file=>/^(?:licen[cs]e|copying|notice)(?:[._-]|$)/i.test(file)&&fs.statSync(path.join(pkg.directory,file)).isFile());
 const supplemental=path.join(root,'docs/third-party-licenses',pkg.name.replaceAll('/','-')+'-'+pkg.version+'-LICENSE.txt');
 sections.push(`## ${name}\n\nDeclared license: ${typeof pkg.license==='string'?pkg.license:'See upstream license'}\n`);
 if(names.length){for(const file of names)sections.push(fs.readFileSync(path.join(pkg.directory,file),'utf8').trim()+'\n');}
 else if(fs.existsSync(supplemental))sections.push(fs.readFileSync(supplemental,'utf8'));
 else {
  const readme=fs.readdirSync(pkg.directory).find(name=>/^readme/i.test(name));
  const excerpt=readme?fs.readFileSync(path.join(pkg.directory,readme),'utf8').match(/(?:^|\n)(?:#+\s*License[^\n]*\n|License\s*\n[-=]+\n)([\s\S]*)/i)?.[1]:null;
  if(!excerpt||!/Permission (?:is hereby granted|to use, copy)/.test(excerpt))throw new Error('Review missing license text before distributing: '+name);
  sections.push(excerpt.trim()+'\n');
 }
}
const sparkle=path.join(root,'desktop/macos/.build/checkouts/Sparkle/LICENSE');
if(!fs.existsSync(sparkle))throw new Error('Resolve the pinned Sparkle package before generating distribution notices.');
sections.push('## Sparkle 2.10.0\n\n'+fs.readFileSync(sparkle,'utf8'));
sections.push('## Node.js\n\nThe macOS app bundles an official Node.js runtime. Its complete LICENSE file, including bundled library notices, is included as Node-LICENSE.txt in the app resources.\n');
fs.writeFileSync(path.join(root,'docs/THIRD_PARTY_NOTICES.md'),sections.join('\n'));
console.log(`Recorded license text for ${packages.size} bundled JavaScript packages and Sparkle.`);
