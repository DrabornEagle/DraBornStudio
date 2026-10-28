#!/usr/bin/env python3
"""Run checksum-pinned Gitleaks with a positive detection control and redacted reports."""
from pathlib import Path
import argparse
import hashlib
import io
import json
import os
import platform
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
VERSION = '8.30.1'
ARCHIVES = {
    ('Darwin', 'arm64'): ('darwin_arm64', 'b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5'),
    ('Darwin', 'x86_64'): ('darwin_x64', 'dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709'),
    ('Linux', 'x86_64'): ('linux_x64', '551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report-dir', type=Path, default=ROOT / 'local/security-scan')
    args = parser.parse_args()
    reports = args.report_dir.resolve()
    reports.mkdir(parents=True, exist_ok=True)
    suffix, checksum = ARCHIVES[(platform.system(), platform.machine())]
    url = f'https://github.com/gitleaks/gitleaks/releases/download/v{VERSION}/gitleaks_{VERSION}_{suffix}.tar.gz'
    request = urllib.request.Request(url, headers={'User-Agent': 'ClipBoardLine-source-security-check'})
    archive = urllib.request.urlopen(request, timeout=60).read()
    if hashlib.sha256(archive).hexdigest() != checksum:
        raise SystemExit('Pinned secret-scanner checksum did not match')
    with tempfile.TemporaryDirectory(prefix='clipboardline-secret-scanner-') as temporary:
        executable = Path(temporary) / 'gitleaks'
        with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as tar:
            entry = tar.getmember('gitleaks')
            if not entry.isfile():
                raise SystemExit('Secret-scanner archive has an invalid executable')
            executable.write_bytes(tar.extractfile(entry).read())
        os.chmod(executable, 0o700)
        base = [str(executable), '--no-banner', '--redact=100', '--report-format', 'json']
        probe = Path(temporary) / 'probe.json'
        # A fresh, throwaway in-memory key proves the detector actually runs.
        # It never authorizes anything, reaches disk, or enters a public report.
        dummy = subprocess.check_output(['openssl', 'genrsa', '2048'], text=True, stderr=subprocess.DEVNULL)
        control = subprocess.run(base + ['--report-path', str(probe), 'stdin'], input=dummy, text=True,
                                 capture_output=True, cwd=ROOT)
        if control.returncode != 1 or not probe.exists() or not json.loads(probe.read_text()):
            raise SystemExit('Secret scanner failed its positive detection control')
        operations = [('working-tree', ['dir', '.'])]
        if subprocess.run(['git', 'rev-parse', '--verify', 'HEAD'], cwd=ROOT, capture_output=True).returncode == 0:
            operations.append(('all-public-history', ['git', '.', '--log-opts=--all']))
        for name, operation in operations:
            report = reports / (name + '.json')
            result = subprocess.run(base + ['--config', '.gitleaks.toml', '--report-path', str(report)] + operation,
                                    capture_output=True, text=True, cwd=ROOT)
            (reports / (name + '.log')).write_text(result.stdout + result.stderr)
            if result.returncode != 0:
                raise SystemExit(f'Secret scan rejected {name}; inspect the redacted report')
            print(f'Gitleaks {VERSION}: {name} passed; positive detection control passed')


if __name__ == '__main__':
    main()
