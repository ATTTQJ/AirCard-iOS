#!/usr/bin/env python3
"""Validate packaging without claiming any on-device compatibility."""
import plistlib
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    root = 'Payload/AirCard-iOS.app/'
    info = plistlib.loads(archive.read(root + 'Info.plist'))
    assert info['CFBundleIdentifier'] == 'com.atttqj.aircard.webclip', info['CFBundleIdentifier']
    assert info['CFBundleDisplayName'] == 'AirCard WebClip'
    assert archive.getinfo(root + info['CFBundleExecutable']).file_size > 0
    assert not any('/_CodeSignature/' in name for name in archive.namelist())
    assert root + 'embedded.mobileprovision' not in archive.namelist()
    assert archive.testzip() is None
print('Unsigned IPA structure verified; physical-device behaviour remains untested.')
