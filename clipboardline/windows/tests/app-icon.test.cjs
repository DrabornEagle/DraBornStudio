'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
test('Windows icon contains every required display scale and both installer identities use it',()=>{
 const root=path.resolve(__dirname,'..'),png=fs.readFileSync(path.join(root,'assets/clipboardline.png')),ico=fs.readFileSync(path.join(root,'assets/clipboardline.ico')),pkg=require('../package.json');
 const signature=Buffer.from('89504e470d0a1a0a','hex');assert.ok(png.subarray(0,8).equals(signature));assert.equal(png.readUInt32BE(16),1024);assert.equal(png.readUInt32BE(20),1024);
 assert.equal(ico.readUInt16LE(0),0);assert.equal(ico.readUInt16LE(2),1);assert.equal(ico.readUInt16LE(4),7);let end=6+16*7;
 for(const[index,size]of[16,24,32,48,64,128,256].entries()){
  const at=6+16*index,length=ico.readUInt32LE(at+8),offset=ico.readUInt32LE(at+12);assert.equal(ico[at]||256,size);assert.equal(ico[at+1]||256,size);assert.equal(ico.readUInt16LE(at+4),1);assert.equal(ico.readUInt16LE(at+6),32);assert.equal(offset,end);assert.ok(length>0&&offset+length<=ico.length);
  const frame=ico.subarray(offset,offset+length);assert.ok(frame.subarray(0,8).equals(signature));assert.equal(frame.readUInt32BE(16),size);assert.equal(frame.readUInt32BE(20),size);end=offset+length;
 }
 assert.equal(end,ico.length);for(const configured of[pkg.build.win.icon,pkg.build.nsis.installerIcon,pkg.build.nsis.uninstallerIcon])assert.equal(configured,'assets/clipboardline.ico');
});
