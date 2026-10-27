"""Replay real Xcode 26 Swift coverage, including overlapping closure regions."""
import base64
import io
import json
from pathlib import Path
import zipfile

from coverage import app_report, summarize


def main():
    root = Path('.build/coverage-replay')
    inputs = root / 'inputs'
    inputs.mkdir(parents=True, exist_ok=True)
    fixture = Path(__file__).parent / 'fixtures/xccov-inputs.zip.b64'
    with zipfile.ZipFile(io.BytesIO(base64.decodebytes(fixture.read_bytes()))) as archive:
        archive.extractall(inputs)
    output = root / 'output'
    summarize(inputs, output)
    unit, ui, combined = [app_report(json.loads((output / f'{scope}.json').read_text()))
                          for scope in ['unit', 'ui', 'combined']]
    assert combined['coveredLines'] > max(unit['coveredLines'], ui['coveredLines']), 'Fixture has complementary coverage'
    assert combined['coveredLines'] < unit['coveredLines'] + ui['coveredLines'], 'Overlapping coverage must not be counted twice'


if __name__ == '__main__':
    main()
