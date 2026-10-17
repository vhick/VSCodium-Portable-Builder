"""Only package the full App / Data / Other / VSCodiumPortable.exe layout."""
from pathlib import Path
import argparse
from build_portable import BuildError, create_zip, expected_asset

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', required=True)
    parser.add_argument('--architecture', choices=['x64','arm64'], required=True)
    args = parser.parse_args()
    expected_asset(args.version, args.architecture)
    src = Path('stage') / 'VSCodiumPortable'
    output = Path('dist') / f'VSCodiumPortable-{args.version}-win-{args.architecture}-AppDataOther.zip'
    if not src.is_dir():
        raise BuildError('Missing the staged application')
    create_zip(src, output)

if __name__ == '__main__':
    main()
