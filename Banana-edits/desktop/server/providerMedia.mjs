import fs from 'node:fs';
import { getWorkspace } from './context.mjs';
export const isSecureReferenceUrl = url => url.protocol==='https:' || (url.protocol==='http:' && url.origin===getWorkspace().origin && !!getWorkspace().mediaKey(url.href));
export const isReferenceUrl = value => {try{const url=new URL(value);return !url.username&&!url.password&&isSecureReferenceUrl(url);}catch{return false;}};
export const providerImageUrl = async (_db,value) => {
  const store=getWorkspace(),key=store.mediaKey(value);if(!key)return value;
  const bytes=fs.readFileSync(store.mediaPath(key));if(Math.ceil(bytes.length/3)*4+64>20*1024*1024)throw new Error('Reference exceeds the image upload limit.');
  const ext=key.split('.').at(-1).toLowerCase();const mime={png:'image/png',jpg:'image/jpeg',jpeg:'image/jpeg',webp:'image/webp'}[ext];if(!mime)throw new Error('Unsupported reference format.');
  return `data:${mime};base64,${bytes.toString('base64')}`;
};
export const providerImageData = providerImageUrl;
