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
    sdk = info['DTSDKName']
    assert sdk.startswith('iphoneos') and int(sdk.removeprefix('iphoneos').split('.')[0]) >= 26, sdk
    assert info.get('UIDesignRequiresCompatibility', False) is False, 'Legacy design compatibility must be disabled'
    assert archive.getinfo(root + info['CFBundleExecutable']).file_size > 0
    assert info['CFBundleShortVersionString'] == '1.3.9', 'IPA version does not match this source'
    assert b'webclip-diagnostics-v4' in archive.read(root + info['CFBundleExecutable']), 'IPA contains an outdated native core'
    assert not any('/_CodeSignature/' in name for name in archive.namelist())
    assert root + 'embedded.mobileprovision' not in archive.namelist()
    assert archive.getinfo(root + 'zh-Hans.lproj/Localizable.strings').file_size > 0
    assert archive.getinfo(root + 'en.lproj/Localizable.strings').file_size > 0
    assert archive.getinfo(root + 'zh-Hans.lproj/InfoPlist.strings').file_size > 0
    assert archive.testzip() is None
print('Unsigned IPA structure verified; physical-device behaviour remains untested.')
