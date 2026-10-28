#!/usr/bin/env python3
"""Reproduce the pinned Apple MobileCLIP-S2 FP32 ONNX assets (build time only).

Use an isolated Python environment with torch==2.5.1 torchvision==0.20.1
onnx==1.17.0 onnxruntime==1.20.1 timm==0.9.16 regex==2024.11.6
Pillow==13.0.0 numpy==2.5.4. This exporter deliberately does not import Apple's
package initializer, which otherwise imports an unrelated open_clip tokenizer.
The actual unmodified CLIP model and reparameterization code are imported from
the reviewed, clean Apple source revision. Tokenization mirrors our Mac adapter.
"""
from __future__ import annotations
import argparse, hashlib, importlib.metadata, json, shutil, subprocess, sys, types, zipfile
from pathlib import Path

SOURCE_REVISION = '341ef058802f0e4e5ab13c02f0cb32a3a94e367b'
CHECKPOINT_REVISION = '6da8f9f1c7fa5ae89385ef86bfdee297d105e6f6'
CHECKPOINT_SHA = '063a87b2a846791bcffafa9f7670ec3968d572a3e7f99e5e4b14348006631d6f'
CHECKPOINT_SIZE = 398067246
TOKENIZER_REVISION = '48faa0fea4b08d74188b3841771aca6ff2c92852'
VERSION = 'mobileclip-s2-onnx-fp32-v1'
TOKENIZER_FILES = {
    'clip-vocab.json': {'sha256':'7aeb221a2a93047170070379743b49204c13d6993d9947323cd94b75c1f657ba','bytes':1197317},
    'clip-merges.txt': {'sha256':'7e0847f6fced8bd28a736dcaeab20e64ac19010771700197ba479a0a8e517d4f','bytes':3194958},
}
PINNED = {'torch':'2.5.1','torchvision':'0.20.1','onnx':'1.17.0','onnxruntime':'1.20.1','timm':'0.9.16','regex':'2024.11.6','Pillow':'13.0.0','numpy':'2.5.4'}

def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as stream:
        while block:=stream.read(1024*1024): h.update(block)
    return {'sha256':h.hexdigest(),'bytes':Path(path).stat().st_size}

def require(condition,message):
    if not condition: raise RuntimeError(message)

def tokenizer(directory):
    import regex
    vocab=json.loads((directory/'clip-vocab.json').read_text())
    merges=(directory/'clip-merges.txt').read_text().splitlines()[1:49152-256-2+1]
    ranks={line:index for index,line in enumerate(merges)}
    byte_values=list(range(33,127))+list(range(161,173))+list(range(174,256));characters=byte_values.copy();extra=0
    for value in range(256):
        if value not in byte_values: byte_values.append(value);characters.append(256+extra);extra+=1
    mapping=dict(zip(byte_values,map(chr,characters)))
    pattern=regex.compile(r"<\|startoftext\|>|<\|endoftext\|>|'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+",regex.I)
    def encode(text):
        import numpy as np
        tokens=[49406]
        for token in pattern.findall(' '.join(text.lower().split())):
            pieces=list(''.join(mapping[value] for value in token.encode('utf-8')));pieces[-1]+='</w>'
            while len(pieces)>1:
                candidates=[(ranks.get(pieces[index]+' '+pieces[index+1],10**10),index) for index in range(len(pieces)-1)]
                rank,index=min(candidates)
                if rank==10**10: break
                first,second=pieces[index:index+2];merged=[];index=0
                while index<len(pieces):
                    if index<len(pieces)-1 and pieces[index:index+2]==[first,second]:merged.append(first+second);index+=2
                    else: merged.append(pieces[index]);index+=1
                pieces=merged
            tokens.extend(vocab[piece] for piece in pieces if piece in vocab)
        tokens=tokens[:76]+[49407]
        return np.array([tokens+[0]*(77-len(tokens))],dtype=np.int64)
    return encode

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apple-source',required=True,type=Path)
    parser.add_argument('--checkpoint',required=True,type=Path)
    parser.add_argument('--tokenizer-directory',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--archive',type=Path)
    args=parser.parse_args();source=args.apple_source.resolve();output=args.output.resolve()
    require(subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()==SOURCE_REVISION,'Apple source revision differs from reviewed source')
    require(not subprocess.check_output(['git','-C',str(source),'status','--porcelain'],text=True).strip(),'Apple source checkout must be unmodified')
    require(digest(args.checkpoint)=={'sha256':CHECKPOINT_SHA,'bytes':CHECKPOINT_SIZE},'Checkpoint size/hash mismatch')
    for name,expected in TOKENIZER_FILES.items():require(digest(args.tokenizer_directory/name)==expected,'Tokenizer differs from the reviewed Mac assets: '+name)
    versions={name:importlib.metadata.version(name).split('+')[0] for name in PINNED}
    require(versions==PINNED,'Export dependencies differ from pinned versions: '+json.dumps(versions))
    import numpy as np, torch, onnx, onnxruntime as ort
    from PIL import Image, ImageDraw
    torch.manual_seed(0);torch.set_num_threads(4);torch.set_num_interop_threads(1)
    package=types.ModuleType('mobileclip');package.__path__=[str(source/'mobileclip')];sys.modules['mobileclip']=package
    from mobileclip.clip import CLIP
    from mobileclip.modules.common.mobileone import reparameterize_model
    cfg=json.loads((source/'mobileclip/configs/mobileclip_s2.json').read_text())
    model=CLIP(cfg=cfg).cpu().eval()
    # No pickle-based arbitrary classes or globals are permitted in weights.
    weights=torch.load(args.checkpoint,map_location='cpu',weights_only=True)
    model.load_state_dict(weights,strict=True);del weights
    model=reparameterize_model(model).cpu().eval()
    class ImageEncoder(torch.nn.Module):
        def __init__(self,clip):super().__init__();self.encoder=clip.image_encoder
        def forward(self,image):
            value=self.encoder(image)
            return value['logits'] if isinstance(value,dict) else value
    class TextEncoder(torch.nn.Module):
        def __init__(self,clip):super().__init__();self.encoder=clip.text_encoder
        def forward(self,text):return self.encoder(text_tokens=text,key_padding_mask=None)
    output.mkdir(parents=True,exist_ok=True)
    encode=tokenizer(args.tokenizer_directory)
    queries=['a red circle on a white background','a blue square on a white background']
    images=[]
    for kind,color in [('circle','red'),('square','blue')]:
        image=Image.new('RGB',(256,256),'white');draw=ImageDraw.Draw(image)
        (draw.ellipse if kind=='circle' else draw.rectangle)((48,48,208,208),fill=color)
        images.append(np.asarray(image,dtype=np.float32).transpose(2,0,1)[None]/255)
    inputs={'image':images[0],'text':encode(queries[0])}
    modules={'image':ImageEncoder(model).eval(),'text':TextEncoder(model).eval()}
    for kind,module in modules.items():
        target=output/f'mobileclip-s2-{kind}.onnx'
        with torch.inference_mode():torch.onnx.export(module,torch.from_numpy(inputs[kind]),str(target),opset_version=17,input_names=[kind],output_names=['embedding'],do_constant_folding=True,dynamo=False)
        model_proto=onnx.load(str(target),load_external_data=False);onnx.checker.check_model(model_proto)
        require(not any(tensor.data_location==onnx.TensorProto.EXTERNAL for tensor in model_proto.graph.initializer),'External ONNX weight files are not permitted')
        print('Exported',target.name,json.dumps(digest(target)),flush=True)
    session_options=ort.SessionOptions();session_options.intra_op_num_threads=2;session_options.inter_op_num_threads=1
    sessions={kind:ort.InferenceSession(str(output/f'mobileclip-s2-{kind}.onnx'),sess_options=session_options,providers=['CPUExecutionProvider']) for kind in modules}
    def unit(value):
        value=np.asarray(value,dtype=np.float32);return value/np.linalg.norm(value,axis=-1,keepdims=True)
    image_vectors=[];text_vectors=[];comparisons=[]
    for kind,values in [('image',images),('text',[encode(query) for query in queries])]:
        for index,value in enumerate(values):
            with torch.inference_mode():reference=modules[kind](torch.from_numpy(value)).numpy()
            actual=sessions[kind].run(['embedding'],{kind:value})[0]
            require(actual.shape==(1,512) and actual.dtype==np.float32 and np.isfinite(actual).all(),'Invalid ONNX output')
            cosine=float((unit(reference)*unit(actual)).sum());require(cosine>0.9999,'Torch/ONNX cosine mismatch')
            comparisons.append({'encoder':kind,'fixture':index,'cosine':cosine,'maximumAbsoluteError':float(np.max(np.abs(reference-actual)))})
            (image_vectors if kind=='image' else text_vectors).append(unit(actual)[0])
    scores=np.asarray(text_vectors)@np.asarray(image_vectors).T
    require(scores[0,0]>scores[0,1] and scores[1,1]>scores[1,0],'Semantic color/shape ranking failed')
    copies={'clip-vocab.json':args.tokenizer_directory/'clip-vocab.json','clip-merges.txt':args.tokenizer_directory/'clip-merges.txt',
            'LICENSE-Apple-code':source/'LICENSE','LICENSE-MobileCLIP-S2':source/'LICENSE_weights_data','ACKNOWLEDGEMENTS-MobileCLIP':source/'ACKNOWLEDGEMENTS'}
    for name,original in copies.items():shutil.copyfile(original,output/name)
    names=['mobileclip-s2-image.onnx','mobileclip-s2-text.onnx',*copies]
    receipt={'schemaVersion':1,'version':VERSION,'model':'MobileCLIP-S2','sourceRepository':'https://github.com/apple/ml-mobileclip','sourceRevision':SOURCE_REVISION,
             'checkpointRepository':'https://huggingface.co/apple/MobileCLIP-S2','checkpointRevision':CHECKPOINT_REVISION,'checkpointSHA256':CHECKPOINT_SHA,'checkpointBytes':CHECKPOINT_SIZE,
             'tokenizerRevision':TOKENIZER_REVISION,'opset':17,'precision':'float32','exportingVersions':versions,
             'inputs':{'image':{'type':'float32','shape':[1,3,256,256],'range':[0,1]},'text':{'type':'int64','shape':[1,77]}},
             'output':{'name':'embedding','type':'float32','shape':[1,512],'normalization':'L2 in the application backend'},
             'files':{name:digest(output/name) for name in names},
             'verification':{'provider':'CPUExecutionProvider','minimumCosine':0.9999,'torchVersusONNX':comparisons,'queries':queries,'imageFixtures':['red-circle','blue-square'],'cosineScores':scores.tolist(),'rankingPassed':True}}
    (output/'model-source.json').write_text(json.dumps(receipt,indent=2)+'\n')
    archive_receipt=None
    if args.archive:
        args.archive.parent.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(args.archive,'w',compression=zipfile.ZIP_STORED) as archive:
            for file in sorted(output.iterdir()):
                require(file.is_file() and not file.is_symlink(),'Unsafe output file')
                entry=zipfile.ZipInfo(file.name,date_time=(2026,10,20,0,0,0));entry.external_attr=0o100644<<16
                archive.writestr(entry,file.read_bytes())
        archive_receipt=digest(args.archive)
    print(json.dumps({'version':VERSION,'output':str(output),'files':{file.name:digest(file) for file in sorted(output.iterdir())},'archive':archive_receipt,'verification':receipt['verification']},indent=2),flush=True)

if __name__=='__main__':main()
