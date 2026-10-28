# Offline semantic image search on Windows

Windows uses Apple's MobileCLIP-S2 through CPU ONNX Runtime. The image/text
encoders, 512-dimensional embedding space and tokenizer match the Mac feature.
Image input is RGB float32, NCHW `[1,3,256,256]` in `[0,1]`; text input is int64
`[1,77]`. Both output float32 `[1,512]`. The backend normalizes each vector to
unit length and preserves the Mac letterbox/tile and aspect-ratio policy.

Models are bundled at build time, and queries and images stay on the computer.
The running app does not download models, send queries or make inference calls
to a service. Source builds run:

```sh
python3 scripts/prepare-windows-search-models.py
python3 scripts/prepare-windows-search-models.py --check
```

Preparation checks the committed archive size/SHA-256 before extraction, checks
each file's exact size/hash and provenance, and rejects duplicate/unexpected
paths, symlinks, encrypted entries and extraction sizes outside the pin. The
assets come from an auxiliary **non-Latest** release in the existing project
repository. It does not replace either application's normal signed update feed.

## Reproducing the export

The unmodified [Apple source](https://github.com/apple/ml-mobileclip/tree/341ef058802f0e4e5ab13c02f0cb32a3a94e367b)
is pinned to `341ef058802f0e4e5ab13c02f0cb32a3a94e367b`. The original
[Apple MobileCLIP-S2 checkpoint](https://huggingface.co/apple/MobileCLIP-S2/tree/6da8f9f1c7fa5ae89385ef86bfdee297d105e6f6)
is pinned to `6da8f9f1c7fa5ae89385ef86bfdee297d105e6f6`, with SHA-256
`063a87b2a846791bcffafa9f7670ec3968d572a3e7f99e5e4b14348006631d6f` and
398,067,246 bytes. Checkpoint loading requires `weights_only=True` and strict
state-dictionary matching. No arbitrary checkpoint classes are enabled.

Use an isolated Python environment with `torch==2.5.1`, `torchvision==0.20.1`,
`onnx==1.17.0`, `onnxruntime==1.20.1`, `timm==0.9.16`, `regex==2024.11.6`,
`Pillow==13.0.0` and `numpy==2.5.4`. Give the exporter the verified Apple source,
checkpoint, and the existing Mac tokenizer directory:

```sh
python scripts/export-windows-search-models.py \
  --apple-source PATH_TO_PINNED_APPLE_CHECKOUT \
  --checkpoint PATH_TO_PINNED_mobileclip_s2.pt \
  --tokenizer-directory PATH_TO_MAC_MobileCLIP \
  --output windows/assets/CLIP \
  --archive PATH_TO_OUTPUT/clipboard-app-MobileCLIP-S2-ONNX-v1.zip
```

The exporter folds Apple's reparameterizable inference branches, exports fixed
opset-17 FP32 graphs with no external weights, and checks the graph format. It
compares actual Torch/CPU ONNX inference on two synthetic images and two queries;
each encoder must exceed cosine 0.9999. The queries must independently rank a
red circle over a blue square, and a blue square over a red circle. Export v1
passes with minimum cosine 0.99999994. This numerical export check complements
the application's real Windows WASM/CPU acceptance and does not replace it.

`model-source.json` records original revisions/checkpoint hash, input/output
contracts, export dependency versions, all asset hashes and the numerical
acceptance results. `windows/search-model-config.json` additionally pins the
manifest and complete release archive. The Apple code/model licenses and
acknowledgements are included in the source assets and installed resources.
Keep the generated ONNX files/archive out of Git; do not remove their licenses.
