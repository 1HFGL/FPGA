"""无损重排原始模态参数表；原表和音色公式保持唯一来源。"""
from pathlib import Path
import argparse
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'rtl/rom/piano_v3_modes.mem'


def packed_tables(source):
    words = source.read_text(encoding='ascii').split()
    if len(words) != 16384 or any(len(w) != 19 or int(w, 16) >= 2**75 for w in words):
        raise ValueError('Expected 2 presets * 128 notes * 64 words, 75 payload bits')
    # 每音末尾16项从未被调度，且必须保持原始的静音参数。
    if any(int(words[n * 64 + k], 16) != 1024 for n in range(256) for k in range(48, 64)):
        raise ValueError('Unused modal slots are no longer the canonical silent tuple')
    return [(Path(str(source) + f'.bank{bank}.mem'),
             '\n'.join(words[n * 64 + bank * 16 + k].lower()
                       for n in range(256) for k in range(16)) + '\n')
            for bank in range(3)]


def check(source=SOURCE):
    tables = packed_tables(source)
    for path, body in tables:
        if not path.is_file() or path.read_bytes() != body.encode('ascii'):
            raise ValueError('Missing/stale packed modal ROM: ' + str(path))
    return {'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'words': 12288, 'banks': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                     for p, _ in tables}}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=SOURCE)
    parser.add_argument('--write', action='store_true', help='Explicitly regenerate the derived banks')
    args = parser.parse_args()
    if args.write:
        for path, body in packed_tables(args.source):
            path.write_bytes(body.encode('ascii'))
    print('PASS modal ROM packing: ' + json.dumps(check(args.source)))
