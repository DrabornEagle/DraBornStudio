#!/usr/bin/env python3
"""Fetch and verify the pinned ONNX models during build; never at app runtime."""
from __future__ import annotations
import argparse, hashlib, json, re, stat, tempfile, urllib.parse, urllib.request, zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
URL='https://github.com/orkunisitmak/clipboardline-desktop/releases/download/models-mobileclip-s2-v1/ClipBoardLine-MobileCLIP-S2-ONNX-v1.zip'
NAMES={'mobileclip-s2-image.onnx','mobileclip-s2-text.onnx','clip-vocab.json','clip-merges.txt','LICENSE-Apple-code','LICENSE-MobileCLIP-S2','ACKNOWLEDGEMENTS-MobileCLIP','model-source.json'}
MAXIMUM=600*1024*1024

def require(condition,message):
    if not condition:raise RuntimeError(message)

def digest(file):
    value=hashlib.sha256();count=0
    with Path(file).open('rb') as stream:
        while block:=stream.read(1024*1024):value.update(block);count+=len(block)
    return {'sha256':value.hexdigest(),'bytes':count}

def config_at(file):
    config=json.loads(file.read_text())
    require(config.get('schemaVersion')==1 and config.get('version')=='mobileclip-s2-onnx-fp32-v1','Unsupported model configuration')
    require(config.get('sourceRevision')=='341ef058802f0e4e5ab13c02f0cb32a3a94e367b','Unexpected Apple source')
    require(config.get('checkpointSHA256')=='063a87b2a846791bcffafa9f7670ec3968d572a3e7f99e5e4b14348006631d6f','Unexpected checkpoint')
    require(config.get('archive',{}).get('url')==URL,'Model download must use the canonical public project release')
    require(isinstance(config.get('files'),dict) and set(config['files'])==NAMES,'Pinned model asset set differs')
    for entry in [config['archive'],*config['files'].values()]:
        require(isinstance(entry,dict) and isinstance(entry.get('sha256'),str) and re.fullmatch('[0-9a-f]{64}',entry['sha256']) and type(entry.get('bytes'))is int and 0<entry['bytes']<=MAXIMUM,'Invalid model asset hash or size')
    require(sum(entry['bytes'] for entry in config['files'].values())<=MAXIMUM,'Model extraction exceeds size bound')
    return config

def verified(directory,config):
    require(directory.is_dir() and not directory.is_symlink(),'Prepared model directory is missing or unsafe')
    require({file.name for file in directory.iterdir()}==NAMES,'Prepared model directory has unexpected files')
    for name,expected in config['files'].items():
        file=directory/name;require(file.is_file() and not file.is_symlink(),'Unsafe model asset: '+name)
        require(digest(file)==expected,'Model asset failed size/hash verification: '+name)
    manifest=json.loads((directory/'model-source.json').read_text())
    require(manifest.get('version')==config['version'] and manifest.get('sourceRevision')==config['sourceRevision'] and manifest.get('checkpointSHA256')==config['checkpointSHA256'],'Model provenance differs')
    require(manifest.get('files')=={name:entry for name,entry in config['files'].items() if name!='model-source.json'},'Model manifest hashes differ')
    require(manifest.get('verification',{}).get('rankingPassed')is True,'Model export has no successful semantic acceptance')
    return True

class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,request,fp,code,message,headers,newurl):
        parsed=urllib.parse.urlparse(newurl)
        require(parsed.scheme=='https' and parsed.hostname in {'github.com','objects.githubusercontent.com','release-assets.githubusercontent.com'} and not parsed.username and not parsed.password,'Unexpected model download redirect')
        return super().redirect_request(request,fp,code,message,headers,newurl)

def extract(archive,destination,config):
    require(archive.is_file() and not archive.is_symlink(),'Model archive is missing or unsafe')
    require(digest(archive)=={key:config['archive'][key] for key in ('sha256','bytes')},'Model archive size/hash mismatch')
    with zipfile.ZipFile(archive) as bundle:
        entries=bundle.infolist();require(len(entries)==len(NAMES) and {entry.filename for entry in entries}==NAMES,'Model archive contains missing, duplicate or unexpected paths')
        for entry in entries:
            require('/'not in entry.filename and '\\'not in entry.filename and not entry.is_dir() and not(entry.flag_bits&1),'Unsafe model archive entry')
            mode=entry.external_attr>>16
            require(not stat.S_ISLNK(mode) and (stat.S_IFMT(mode) in (0,stat.S_IFREG)),'Model archive entries must be regular files')
            expected=config['files'][entry.filename];require(entry.file_size==expected['bytes'] and entry.compress_type in (zipfile.ZIP_STORED,zipfile.ZIP_DEFLATED),'Model archive entry size/type mismatch')
            value=hashlib.sha256();count=0
            with bundle.open(entry) as source,(destination/entry.filename).open('xb') as output:
                while block:=source.read(1024*1024):
                    count+=len(block);require(count<=expected['bytes'],'Model extraction exceeded declared size');value.update(block);output.write(block)
            require(count==expected['bytes'] and value.hexdigest()==expected['sha256'],'Model archive entry digest mismatch')
            (destination/entry.filename).chmod(0o644)
    verified(destination,config)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',type=Path,default=ROOT/'windows/search-model-config.json')
    parser.add_argument('--output',type=Path,default=ROOT/'windows/assets/CLIP')
    parser.add_argument('--archive',type=Path,help='Use an already downloaded archive; identical hashes are mandatory')
    parser.add_argument('--check',action='store_true',help='Verify the prepared directory without downloading')
    args=parser.parse_args();config=config_at(args.config)
    output=args.output.absolute();require(not output.is_symlink(),'Model output must not be a symlink')
    if output.exists():
        verified(output,config);print('Pinned MobileCLIP-S2 models and licenses verified');return
    require(not args.check,'Pinned model directory has not been prepared')
    output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.mobileclip-prepare-',dir=output.parent) as temporary:
        work=Path(temporary);archive=args.archive
        if archive is None:
            archive=work/'models.zip';entry=config['archive'];count=0;value=hashlib.sha256()
            opener=urllib.request.build_opener(SafeRedirect())
            with opener.open(urllib.request.Request(entry['url'],headers={'User-Agent':'ClipBoardLine-build-model-preparation/1'}),timeout=60) as response,archive.open('xb') as target:
                advertised=response.headers.get('Content-Length');require(advertised is None or int(advertised)==entry['bytes'],'Model download advertised unexpected length')
                while block:=response.read(1024*1024):
                    count+=len(block);require(count<=entry['bytes'],'Model download exceeded size limit');value.update(block);target.write(block)
            require(count==entry['bytes'] and value.hexdigest()==entry['sha256'],'Downloaded model archive failed verification')
        prepared=work/'prepared';prepared.mkdir();extract(archive,prepared,config)
        require(not output.exists(),'Model output appeared while preparing assets');prepared.rename(output)
    print('Prepared pinned MobileCLIP-S2 models; runtime performs no model or query requests')

if __name__=='__main__':main()
