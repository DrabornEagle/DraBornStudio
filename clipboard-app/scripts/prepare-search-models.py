#!/usr/bin/env python3
"""Fetch pinned original MobileCLIP-S2 assets for offline, on-device search."""
import hashlib, json, pathlib, subprocess, urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / 'local/models/MobileCLIP'
REV = '3e0a7bfb9fe83da8a3efaa3fd8f7df24214bb947'
# Original S2 release, distributed as Apple Sample Code (also declared by the
# pinned apple/coreml-mobileclip model card). MobileCLIP2 is a different release.
APPLE = '341ef058802f0e4e5ab13c02f0cb32a3a94e367b'
TOKENIZER = '48faa0fea4b08d74188b3841771aca6ff2c92852'
FILES = {
 'mobileclip_s2_image.mlpackage/Data/com.apple.CoreML/model.mlmodel': '2aeb3359f6cde65e9f9248ec2a742e9939bd4bbf48c2f55fcd255b4504d96a1b',
 'mobileclip_s2_image.mlpackage/Data/com.apple.CoreML/weights/weight.bin': '6cbc7fb06b6072c1cae9c4496d67e0e6217adbf726dfeb82e44d4efe87c34c00',
 'mobileclip_s2_text.mlpackage/Data/com.apple.CoreML/model.mlmodel': 'b8651b6d030bae419a9548b41c8fae11f96b59cfa21b6e532a4c4434522b4b80',
 'mobileclip_s2_text.mlpackage/Data/com.apple.CoreML/weights/weight.bin': '8e8d5454f104b6cbb58d98bf11e038ff1f1943599efea111260a832f094cd0ce',
}

def fetch(url, path, expected=None):
    if path.is_file() and (expected is None or hashlib.sha256(path.read_bytes()).hexdigest() == expected): return
    path.parent.mkdir(parents=True, exist_ok=True)
    stage = path.with_name(path.name + '.download')
    req = urllib.request.Request(url, headers={'User-Agent': 'ClipboardLine-model-build'})
    with urllib.request.urlopen(req, timeout=120) as response, stage.open('wb') as f:
        while chunk := response.read(1024 * 1024): f.write(chunk)
    if expected and hashlib.sha256(stage.read_bytes()).hexdigest() != expected:
        raise RuntimeError('Model checksum mismatch: ' + path.name)
    stage.replace(path)

OUT.mkdir(parents=True, exist_ok=True)
for name in ['mobileclip_s2_image', 'mobileclip_s2_text']:
    for suffix in ['Manifest.json', 'Data/com.apple.CoreML/model.mlmodel', 'Data/com.apple.CoreML/weights/weight.bin']:
        path = name + '.mlpackage/' + suffix
        fetch(f'https://huggingface.co/apple/coreml-mobileclip/resolve/{REV}/{path}', OUT / path, FILES.get(path))
    if not (OUT / (name + '.mlmodelc')).is_dir():
        subprocess.run(['xcrun', 'coremlcompiler', 'compile', str(OUT / (name + '.mlpackage')), str(OUT)], check=True)
for name in ['clip-vocab.json', 'clip-merges.txt']:
    fetch(f'https://raw.githubusercontent.com/apple-aiml-research/ml-mobileclip/{TOKENIZER}/ios_app/MobileCLIPExplore/Resources/{name}', OUT / name)
fetch(f'https://raw.githubusercontent.com/apple-aiml-research/ml-mobileclip/{APPLE}/LICENSE_weights_data', OUT / 'LICENSE-MobileCLIP-S2')
fetch(f'https://raw.githubusercontent.com/apple-aiml-research/ml-mobileclip/{APPLE}/LICENSE', OUT / 'LICENSE-Apple-code')
fetch(f'https://raw.githubusercontent.com/apple-aiml-research/ml-mobileclip/{APPLE}/ACKNOWLEDGEMENTS', OUT / 'ACKNOWLEDGEMENTS-MobileCLIP')
(OUT / 'model-source.json').write_text(json.dumps({'model': 'MobileCLIP-S2', 'revision': REV, 'tokenizerRevision': TOKENIZER, 'originalModelLicenseRevision': APPLE, 'sha256': FILES}, indent=2) + '\n')
print('Prepared offline search models:', OUT)
