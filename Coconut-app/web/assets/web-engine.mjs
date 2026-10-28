import { FFmpeg } from './vendor/ffmpeg/index.js';
import { mediaPlan, mediaMimes } from './media-plan.mjs';
let engine, pending, locked = false;
const core = 'https://cdn.jsdelivr.net/npm/@ffmpeg/core@0.12.10/dist/esm/';
async function resource(name, type) {
  const response = await fetch(core + name);
  if (!response.ok) throw new Error('Medya motoru indirilemedi. İnternet bağlantını kontrol et.');
  return URL.createObjectURL(new Blob([await response.arrayBuffer()], { type }));
}
async function load(status) {
  if (engine?.loaded) return engine;
  if (!pending) pending = (async () => {
    status('Medya motoru indiriliyor · ilk kullanımda yaklaşık 31 MB');
    engine = new FFmpeg();
    const resources = await Promise.all([resource('ffmpeg-core.js', 'text/javascript'), resource('ffmpeg-core.wasm', 'application/wasm')]);
    try { await engine.load({ coreURL: resources[0], wasmURL: resources[1] }); }
    finally { resources.forEach(URL.revokeObjectURL); }
    return engine;
  })().catch(error => { pending = null; engine = null; throw error; });
  return pending;
}
export function cancelMedia() { engine?.terminate(); engine = null; pending = null; }
export async function processMedia(files, id, values, status, conversion) {
  if (locked) throw new Error('Diğer işlemin tamamlanmasını bekle.');
  locked = true;
  const written = []; let progress;
  try {
    const ff = await load(status);
    progress = ({ progress }) => status(`İşleniyor · %${Math.min(99, Math.max(0, Math.round(progress * 100)))}`);
    ff.on('progress', progress);
    const names = files.map((f, i) => `input${i}.${String(f.ext).replace(/[^a-z0-9]/gi,'')}`);
    for (let i = 0; i < files.length; i++) {
      const bytes = files[i].blob ? new Uint8Array(await files[i].blob.arrayBuffer()) : new Uint8Array(await (await fetch(files[i].url)).arrayBuffer());
      if (bytes.length > 128 * 1024 * 1024) throw new Error('Tarayıcıda dosya başına sınır 128 MB.');
      await ff.writeFile(names[i], bytes); written.push(names[i]);
    }
    const duration = Number(values.duration) || 360000;
    let plans;
    if (id === 'splitVideo') {
      const count = Math.max(2, Math.min(12, Number(values.clips) || 3));
      plans = Array.from({length:count}, (_,i) => mediaPlan('trimVideo', { start:i*duration/count, end:(i+1)*duration/count }, duration, names));
    } else plans = [mediaPlan(id, values, duration, names, conversion)];
    if (id === 'joinVideos') {
      const list = 'inputs.txt'; await ff.writeFile(list, names.map(name => `file '${name}'`).join('\n')); written.push(list);
      plans[0].args = ['-y','-f','concat','-safe','0','-i',list,'-c:v','libx264','-preset','ultrafast','-c:a','aac','-movflags','+faststart'];
    }
    const results = [];
    for (let i=0;i<plans.length;i++) {
      const plan = plans[i], output = `nashi-output-${i}.${plan.ext}`; written.push(output);
      const exit = await ff.exec([...plan.args, output], 180000);
      if (exit !== 0) throw new Error('Bu dosya/codec işlenemedi veya işlem süresi aşıldı. Daha kısa bir dosya veya MP4 / WAV dene.');
      const bytes = await ff.readFile(output);
      if (!bytes.length) throw new Error('Çıktı oluşturulamadı.');
      results.push({ name: files[0].name.replace(/\.[^.]+$/,'') + '-' + (conversion || id) + (plans.length>1?'-'+(i+1):'') + '.'+plan.ext, blob: new Blob([bytes], {type:plan.mime}) });
    }
    return results;
  } finally {
    if (engine?.loaded) { if (progress) engine.off('progress', progress); for(const file of written) try { await engine.deleteFile(file); } catch { /* Already cancelled. */ } }
    locked = false;
  }
}
