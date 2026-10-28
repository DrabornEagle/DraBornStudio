#!/bin/bash
# Build only: synthetic data, isolated preferences, no real clipboard watcher.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
SDK="${SDKROOT:-$(xcrun --show-sdk-path)}"
if [ -z "${SDKROOT:-}" ] && [[ "$DEVELOPER_DIR" == /Library/Developer/CommandLineTools* ]] && [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
  SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
OUT="$PWD/.build/ui-tests"
APP="$PWD/build/ClipboardLine UI Test.app"
python3 - "$APP" <<'PY'
import pathlib,subprocess,sys
executable=str(pathlib.Path(sys.argv[1])/'Contents/MacOS/FeatureTests')
commands=subprocess.check_output(['ps','-A','-o','comm='],text=True).splitlines()
if executable in [command.strip() for command in commands]:
    sys.exit('UI harness is running. Quit it before rebuilding its bundle.')
PY
mkdir -p "$OUT/ModuleCache" "$APP/Contents/MacOS" "$APP/Contents/Resources"
SOURCES=()
for source in Sources/Tendedero/*.swift; do
  [[ "$source" == */main.swift ]] || SOURCES+=("$source")
done
swiftc -O -g -file-prefix-map "$PWD=." -sdk "$SDK" -module-cache-path "$OUT/ModuleCache" \
  -D STANDALONE_TESTS -parse-as-library "${SOURCES[@]}" \
  Tests/ImageHistoryTests/TestFixtures.swift Tests/UITests/UIHarness.swift \
  -o "$APP/Contents/MacOS/FeatureTests"
python3 - "$APP" <<'PY'
from pathlib import Path
import plistlib,sys,shutil,json,subprocess
app=Path(sys.argv[1])
state=json.loads(Path("upstream-state.json").read_text())
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier':'local.clipboardline.uitests',
    'CFBundleName':'ClipboardLine UI Test',
    'CFBundleDisplayName':'ClipboardLine UI Test',
    'CFBundleExecutable':'FeatureTests',
    'CFBundlePackageType':'APPL',
    'CFBundleShortVersionString':state['forkVersion'],
    'CFBundleVersion':state['buildNumber'],
    'ClipboardLineForkRevision':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
    'LSMinimumSystemVersion':'14.0',
    'NSHighResolutionCapable':True,
    'UTExportedTypeDeclarations':[{'UTTypeIdentifier':'local.clipboardline.library-id','UTTypeConformsTo':['public.data'],'UTTypeDescription':'Library item identifier'}],
}))
for resource in Path('Sources/Tendedero/Resources').glob('*.lproj'):
    shutil.copytree(resource,app/'Contents/Resources'/resource.name,dirs_exist_ok=True)
PY
if [ "${CLIPBOARDLINE_BUNDLE_MODELS:-0}" = "1" ]; then
  bash scripts/bundle-search-models.sh "$APP"
fi
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP (not launched)"
