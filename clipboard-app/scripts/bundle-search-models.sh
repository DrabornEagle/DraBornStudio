#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODELS="$PWD/local/models/MobileCLIP"
if [ ! -d "$MODELS/mobileclip_s2_text.mlmodelc" ] || [ ! -f "$MODELS/model-source.json" ] || [ ! -f "$MODELS/ACKNOWLEDGEMENTS-MobileCLIP" ]; then
  python3 scripts/prepare-search-models.py
fi
DEST="$1/Contents/Resources/CLIP"
mkdir -p "$DEST"
for name in mobileclip_s2_image.mlmodelc mobileclip_s2_text.mlmodelc clip-vocab.json clip-merges.txt LICENSE-MobileCLIP-S2 LICENSE-Apple-code ACKNOWLEDGEMENTS-MobileCLIP model-source.json; do
  ditto "$MODELS/$name" "$DEST/$name"
done
