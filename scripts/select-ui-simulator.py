#!/usr/bin/env python3
"""Pick an installed iPhone simulator that can actually render Liquid Glass."""
import json
import subprocess
import sys

def simctl(*args):
    return json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', *args, '-j']))

runtimes = {
    r['identifier']: tuple(int(v) for v in r['version'].split('.'))
    for r in simctl('runtimes')['runtimes']
    if r.get('isAvailable') and r['name'].startswith('iOS') and int(r['version'].split('.')[0]) >= 26
}
candidates = [
    (runtimes[runtime], d['name'] == 'iPhone 16 Pro', d['name'], d['udid'])
    for runtime, devices in simctl('devices', 'available')['devices'].items()
    if runtime in runtimes
    for d in devices if d['name'].startswith('iPhone')
]
if not candidates:
    raise SystemExit('No iOS 26+ iPhone simulator is installed; do not silently test the legacy design.')
version, _, name, identifier = max(candidates)
print(f'UI verification: {name}, iOS {".".join(map(str, version))}', file=sys.stderr)
print(identifier)
