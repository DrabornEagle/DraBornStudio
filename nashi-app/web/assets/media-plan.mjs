export const mediaMimes = { mp4:'video/mp4',mov:'video/quicktime',mkv:'video/x-matroska',webm:'video/webm',avi:'video/x-msvideo',wmv:'video/x-ms-wmv',gif:'image/gif',png:'image/png',jpg:'image/jpeg',webp:'image/webp',bmp:'image/bmp',tiff:'image/tiff',avif:'image/avif',mp3:'audio/mpeg',m4a:'audio/mp4',wav:'audio/wav',flac:'audio/flac',ogg:'audio/ogg',opus:'audio/ogg',aiff:'audio/aiff',wma:'audio/x-ms-wma' };
const finite = (value, fallback) => Number.isFinite(Number(value)) ? Number(value) : fallback;
const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
export function mediaPlan(id, values = {}, duration = 1, files = ['input0.mp4'], conversion) {
  const args = ['-i', files[0]], filters = [], audio = [];
  let ext = conversion || (files[0].match(/\.(wav|mp3|m4a|flac|ogg|opus|aiff|wma)$/i) ? 'wav' : 'mp4');
  const start = clamp(finite(values.start, 0), 0, duration), end = clamp(finite(values.end, duration), start + .01, duration);
  if (['trimVideo','trimAudio','splitVideo'].includes(id)) args.push('-ss', String(start), '-t', String(end - start));
  if (id === 'muteVideo') args.push('-an');
  if (id === 'cropVideo') {
    const width = clamp(finite(values.cropWidth, 75), 10, 100) / 100;
    const ratio = clamp(finite(values.ratio, 16/9), .25, 4);
    filters.push(`crop=w='trunc(min(iw*${width},ih*${ratio})/2)*2':h='trunc(min(ih,iw*${width}/${ratio})/2)*2'`);
  }
  if (id === 'redactVideo') {
    const area = "w=iw*0.5:h=ih*0.5:x=iw*0.25:y=ih*0.25";
    // Solid concealment avoids claiming a blur that could leave legible details.
    filters.push(`drawbox=${area}:color=black:t=fill:enable='between(t,${start},${end})'`);
  }
  if (id === 'changeVideoSpeed') {
    const speed = clamp(finite(values.speed, 1), .25, 2); filters.push(`setpts=PTS/${speed}`);
    audio.push(speed < .5 ? `atempo=0.5,atempo=${speed/.5}` : `atempo=${speed}`);
  }
  if (id === 'normalizeAudio') audio.push(`loudnorm=I=${clamp(finite(values.lufs,-16),-30,-5)}:TP=${clamp(finite(values.peak,-1),-9,0)}:LRA=11`);
  if (id === 'audioChannels') args.push('-ac', values.channels === 'mono' ? '1' : '2');
  if (id === 'trimAudio' && values.silence) audio.push('silenceremove=start_periods=1:start_duration=0.1:start_threshold=-45dB:stop_periods=-1:stop_duration=0.2:stop_threshold=-45dB');
  if (id === 'redactAudio') audio.push(`volume=enable='between(t,${start},${end})':volume=0`);
  if (id === 'audioToVideo') {
    ext = 'mp4'; args.push('-filter_complex', '[0:a]showwaves=s=1280x720:mode=line:colors=0xe8c878,format=yuv420p[v]', '-map', '[v]', '-map', '0:a');
  }
  if (id === 'removeMetadata') args.push('-map_metadata', '-1');
  if (filters.length) args.push('-vf', filters.join(','));
  if (audio.length) args.push('-af', audio.join(','));
  if (['mp4','mov','mkv'].includes(ext)) {
    args.push('-c:v','libx264','-preset','ultrafast','-pix_fmt','yuv420p','-vf', [...filters, 'scale=trunc(iw/2)*2:trunc(ih/2)*2'].join(','));
    if (id !== 'muteVideo') args.push('-c:a','aac');
    if (ext !== 'mkv') args.push('-movflags','+faststart');
    if (id === 'compress') args.push('-crf', String(Math.round(46-clamp(finite(values.quality,75),10,100)*.3)));
  } else if (ext === 'webm') args.push('-c:v','libvpx','-deadline','realtime','-cpu-used','8','-c:a','libopus');
  else if (ext === 'mp3') args.push('-vn','-c:a','libmp3lame','-q:a','3');
  else if (ext === 'm4a') args.push('-vn','-c:a','aac');
  else if (ext === 'wav') args.push('-vn','-c:a','pcm_s16le');
  else if (ext === 'aiff') args.push('-vn','-c:a','pcm_s16be');
  else if (ext === 'flac') args.push('-vn','-c:a','flac');
  else if (['ogg','opus'].includes(ext)) args.push('-vn','-c:a',ext==='opus'?'libopus':'libvorbis');
  else if (['png','jpg','webp','bmp','tiff','avif'].includes(ext)) args.push('-frames:v','1');
  return { args: ['-y', ...args], ext, mime: mediaMimes[ext] || 'application/octet-stream' };
}
