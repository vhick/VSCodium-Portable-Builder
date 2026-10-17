"""Offline safety/layout checks. These don't pretend to test the Windows executable."""
from __future__ import annotations
import sys
from pathlib import Path
import tempfile
import unittest
import zipfile
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).parents[1] / 'builder'))
from build_portable import (
    BuildError, expected_asset, choose_asset, _validate_members, unpack_official_zip,
    enable_portable_mode, create_zip, fetch_release,
)
VERSION = '1.140.06880'
NAME = f'VSCodium-win32-x64-{VERSION}.zip'
TEST_SHA = '0' * 64


def fixture_release():
    return {'tag_name': VERSION, 'draft': False, 'prerelease': False,
            'assets': [{'name': NAME, 'state': 'uploaded', 'size': 200_000_000,
                        'digest': 'sha256:' + TEST_SHA,
                        'browser_download_url': 'https://github.com/VSCodium/vscodium/releases/download/' + VERSION + '/' + NAME}]}


def dummy_official_zip(path, inner_data=False):
    with zipfile.ZipFile(path, 'w') as z:
        z.writestr('VSCodium.exe', 'fake EXE for offline structure test')
        z.writestr('resources/app/product.json', '{}')
        z.writestr('bin/codium.cmd', '@echo off')
        if inner_data:
            z.writestr('data/user-data/my-settings.json', 'critical data')


def dummy_launcher(root):
    (root / 'VSCodiumPortable.exe').write_bytes(b'Mock compiled launcher, NOT REAL EXE')
    app_info = root / 'App' / 'AppInfo'
    for icon in ('appicon.ico', 'appicon_16.png', 'appicon_32.png', 'appicon_128.png'):
        (app_info / icon).write_bytes(b'Mock icon')


class BuilderTests(unittest.TestCase):
    def test_paginated_release_assets(self):
        release = fixture_release()
        release['id'] = 12345
        release['assets'] = []
        page_one = [{'name': f'unrelated-{i}'} for i in range(100)]
        page_two = fixture_release()['assets']
        with patch('build_portable._github_api_json', side_effect=[release, page_one, page_two]) as mocked:
            found = fetch_release(VERSION)
        self.assertEqual(mocked.call_count, 3)
        self.assertEqual(choose_asset(found, VERSION, 'x64')['name'], NAME)

    def test_choose_asset(self):
        self.assertEqual(choose_asset(fixture_release(), VERSION, 'x64')['name'], NAME)
        self.assertEqual(expected_asset(VERSION, 'arm64'), f'VSCodium-win32-arm64-{VERSION}.zip')

    def test_version_restrictions(self):
        for version in ('latest', 'v1.140.06880', '1.140.06880-beta.1', '1.140.06880/../../bad'):
            with self.subTest(version=version), self.assertRaises(BuildError):
                expected_asset(version, 'x64')

    def test_reject_beta_or_draft(self):
        for key in ('prerelease', 'draft'):
            release = fixture_release()
            release[key] = True
            with self.assertRaises(BuildError):
                choose_asset(release, VERSION, 'x64')

    def test_sha256_required(self):
        for value in (None, '', 'md5:' + TEST_SHA, 'sha256:abc'):
            release = fixture_release()
            release['assets'][0]['digest'] = value
            with self.assertRaises(BuildError):
                choose_asset(release, VERSION, 'x64')

    def test_reject_unofficial_asset_url(self):
        release = fixture_release()
        release['assets'][0]['browser_download_url'] = 'https://example.com/evil.zip'
        with self.assertRaises(BuildError):
            choose_asset(release, VERSION, 'x64')

    def test_reject_zip_path_traversal(self):
        with tempfile.TemporaryDirectory() as d:
            src = Path(d) / 'bad.zip'
            with zipfile.ZipFile(src, 'w') as z:
                z.writestr('../escape.txt', 'bad')
            with zipfile.ZipFile(src) as z, self.assertRaises(BuildError):
                _validate_members(z)

    def test_reject_upstream_with_data(self):
        with tempfile.TemporaryDirectory() as d:
            src = Path(d) / 'official.zip'
            dummy_official_zip(src, inner_data=True)
            with self.assertRaises(BuildError):
                unpack_official_zip(src, Path(d) / 'App' / 'VSCodium')

    def test_output_layout_and_launcher_configuration(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            src = tmp / 'official.zip'
            dummy_official_zip(src)
            root = tmp / 'VSCodiumPortable'
            unpack_official_zip(src, root / 'App' / 'VSCodium')
            enable_portable_mode(root, VERSION, 'x64', 'a' * 64)
            self.assertFalse((root / 'App/VSCodium/data').exists())
            self.assertTrue((root / 'Data/VSCodium/user-data').is_dir())
            config = (root / 'App/AppInfo/Launcher/VSCodiumPortable.ini').read_text()
            self.assertIn(r'VSCODE_PORTABLE=%PAL:DataDir%\VSCodium', config)
            self.assertIn(r'TMP=%PAL:DataDir%\VSCodium\tmp', config)
            self.assertNotIn('\t', config)  # Don't let Python escape \t in Windows path!
            dummy_launcher(root)
            zip_path = tmp / 'output.zip'
            create_zip(root, zip_path)
            with zipfile.ZipFile(zip_path) as z:
                files = z.namelist()
                for path in ('VSCodiumPortable/VSCodiumPortable.exe',
                             'VSCodiumPortable/App/VSCodium/VSCodium.exe',
                             'VSCodiumPortable/App/AppInfo/appinfo.ini',
                             'VSCodiumPortable/Data/VSCodium/user-data/',
                             'VSCodiumPortable/Data/VSCodium/extensions/',
                             'VSCodiumPortable/Data/VSCodium/tmp/',
                             'VSCodiumPortable/Other/README-PORTABLE.txt'):
                    self.assertIn(path, files)
                self.assertNotIn('VSCodiumPortable/data/', files)
                self.assertFalse(any(x.startswith('VSCodiumPortable/App/VSCodium/data/') for x in files))

    def test_package_rejects_missing_launcher(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            src = tmp / 'upstream.zip'
            dummy_official_zip(src)
            root = tmp / 'VSCodiumPortable'
            unpack_official_zip(src, root / 'App/VSCodium')
            enable_portable_mode(root, VERSION, 'x64', 'a' * 64)
            with self.assertRaises(BuildError):
                create_zip(root, tmp / 'no-launcher.zip')

    def test_package_rejects_app_local_data(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            src = tmp / 'upstream.zip'
            dummy_official_zip(src)
            root = tmp / 'VSCodiumPortable'
            unpack_official_zip(src, root / 'App/VSCodium')
            enable_portable_mode(root, VERSION, 'x64', 'a' * 64)
            dummy_launcher(root)
            (root / 'App/VSCodium/data').mkdir()
            with self.assertRaises(BuildError):
                create_zip(root, tmp / 'bad.zip')

    def test_launcher_uses_native_portable_env_without_folder_moves(self):
        launcher = (Path(__file__).parents[1] / 'builder/VSCodiumPortable.cs').read_text()
        self.assertIn('start.EnvironmentVariables["VSCODE_PORTABLE"] = dataDir;', launcher)
        self.assertIn('Directory.CreateDirectory(Path.Combine(dataDir, "extensions"));', launcher)
        self.assertIn('Directory.Exists(innerData)', launcher)
        self.assertIn('Process.Start(start)', launcher)
        self.assertNotIn('Directory.Move(', launcher)


if __name__ == '__main__':
    unittest.main()
