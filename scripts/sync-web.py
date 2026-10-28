#!/usr/bin/env python3
"""Build products are generated first; copy only owned application destinations."""
from pathlib import Path
import argparse
import shutil

ROOT = Path(__file__).resolve().parents[1]
SKIP = {'node_modules', '.git', '.build', 'dist', 'build', 'bin', 'obj', '__pycache__'}

def copy_tree(source, destination, extra_skip=()):
    for source_file in source.rglob('*'):
        relative = source_file.relative_to(source)
        if any(part in SKIP or part in extra_skip for part in relative.parts):
            continue
        if not source_file.is_file() or source_file.is_symlink():
            continue
        if source_file.name.startswith('.env') and source_file.name != '.env.example':
            continue
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_file, target)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('website', type=Path)
    args = parser.parse_args()
    website = args.website.resolve()
    if not (website / '.git').exists():
        parser.error('Target must be a checked-out DrabornEagle_Web repository.')
    build = ROOT / 'banana-studio/dist'
    if not (build / 'index.html').is_file():
        parser.error('Run npm run build in banana-studio first.')
    copy_tree(ROOT / 'nashi-app/web', website / 'Coconut-app')
    copy_tree(ROOT / 'nashi-app', website / 'Coconut-app/source', extra_skip={'web'})
    for readme in ('README.md', 'README.tr.md'):
        snapshot = website / 'Coconut-app/source' / readme
        if snapshot.exists():
            snapshot.write_text(snapshot.read_text().replace('](web/WEB_STATUS.md)', '](../WEB_STATUS.md)'))
    copy_tree(ROOT / 'banana-studio', website / 'Banana-edits/source')
    output_assets = website / 'Banana-edits/assets'
    if output_assets.is_dir():
        for old in output_assets.iterdir():
            if old.is_file() and old.suffix in {'.js', '.css', '.map'}:
                old.unlink()
    copy_tree(build, website / 'Banana-edits')
    print('Updated Coconut-app and Banana-edits runtime files and source snapshots.')

if __name__ == '__main__':
    main()
